require 'i18n'
require 'yaml'
require 'set'
require 'lit/services/humanize_service'

module Lit
  class I18nBackend
    include I18n::Backend::Simple::Implementation
    include I18n::Backend::Pluralization

    attr_reader :cache

    def initialize(cache)
      @cache = cache
      @available_locales_cache = nil
      @translations = {}
      reserved_keys = I18n.const_get(:RESERVED_KEYS) + %i[lit_default_copy]
      I18n.send(:remove_const, :RESERVED_KEYS)
      I18n.const_set(:RESERVED_KEYS, reserved_keys.freeze)
    end

    ## DOC
    ## Translation flow starts with Rails-provided ActionView::Helpers::TranslationHelper `translate` method
    ## In that method any calls to `I18n.translate` are catched by this method below (because Lit acts as I18 backend)
    ## Any calls in Lit to `super` go straight to I18n
    def translate(locale, key, options = {})
      options[:lit_default_copy] = options[:default].dup if can_dup_default(options)
      content = super(locale, key, options)

      if on_rails_6_1_or_higher?
        @untranslated_key = key if key.present? && options[:default].instance_of?(Object)

        if key.nil? && options[:lit_default_copy].present?
          update_default_localization(locale, options)
        end
      end

      if Lit.all_translations_are_html_safe && content.respond_to?(:html_safe)
        content.html_safe
      else
        content
      end
    end

    def available_locales
      return @available_locales_cache unless @available_locales_cache.nil?
      @locales ||= ::Rails.configuration.i18n.available_locales
      if @locales && !@locales.empty?
        @available_locales_cache = @locales.map(&:to_sym)
      else
        @available_locales_cache = Lit::Locale.ordered.visible.map { |l| l.locale.to_sym }
      end
      @available_locales_cache
    end

    def reset_available_locales_cache
      @available_locales_cache = nil
    end

    # Stores the given translations.
    #
    # @param [String] locale the locale (ie "en") to store translations for
    # @param [Hash] data nested key-value pairs to be added as blurbs
    def store_translations(locale, data, options = {})
      super
      ActiveRecord::Base.transaction do
        store_item(locale, data)
      end if store_items? && valid_locale?(locale)
    end

    def init_translations_with_caching
      without_store_items { load_translations }
      @cache.load_all_translations
      
      load_yaml_translations_in_batches
    end

    def load_yaml_translations_in_batches
      return if @translations.nil? || @translations.empty?
      
      begin
        new_translations = scan_for_new_yaml_translations
      rescue => e
        @cache.lit_logger.error "Failed to scan for new YAML translations: #{e.message}"
        @cache.lit_logger.error e.backtrace.join("\n") if Rails.env.development?
        new_translations = []
      end
      
      new_translation_keys = Set.new
      new_translations.each do |translation|
        new_translation_keys.add("#{translation[:locale]}.#{translation[:key]}")
      end
      
      all_translations = []
      begin
        @translations.each do |locale, data|
          next unless valid_locale?(locale)
          flatten_translations_for_batching(locale, data, [], all_translations)
        end
      rescue => e
        @cache.lit_logger.error "Failed to flatten translations: #{e.message}"
        @cache.lit_logger.error e.backtrace.join("\n") if Rails.env.development?
        return
      end
      
      if new_translations.any?
        store_new_translations_with_store_item(new_translations)
      end
      
      translations_to_process = []
      processed_keys = Set.new
      skipped_count = 0
      
      all_translations.each do |locale, key, value, is_array|
        full_key = "#{locale}.#{key}"
        
        next if processed_keys.include?(full_key)
        processed_keys.add(full_key)
        
        if new_translation_keys.include?(full_key)
          translations_to_process << [locale, key, value, is_array]
          next
        end

        if translation_exists_in_database?(locale, key)
          skipped_count += 1
          next
        end
        
        translations_to_process << [locale, key, value, is_array]
      end
      
      return if translations_to_process.empty?
      
      batch_size = 1000
      total_batches = (translations_to_process.length / batch_size.to_f).ceil

      @cache.lit_logger.info "Loading #{translations_to_process.length} YAML translations in #{total_batches} batches (batch size: #{batch_size})"
      @cache.lit_logger.info "Found #{new_translations.length} new translations not in database" if new_translations.any?
      @cache.lit_logger.info "Skipped #{skipped_count} existing translations (only new translations are created, existing ones are never updated)" if skipped_count > 0
      
      Thread.current[:lit_cache_keys] = @cache.keys
      
      begin
        translations_to_process.each_slice(batch_size).with_index do |batch, batch_index|
          batch_num = batch_index + 1
          @cache.lit_logger.info "Processing YAML batch #{batch_num}/#{total_batches} (#{batch.length} translations)"
          
          begin
            ActiveRecord::Base.transaction do
              batch.each do |locale, key, value, is_array|
                @cache.update_locale("#{locale}.#{key}", value, is_array, true)
              end
            end
          rescue => e
            @cache.lit_logger.error "Failed to process YAML batch #{batch_num}: #{e.message}"
            @cache.lit_logger.error e.backtrace.join("\n") if Rails.env.development?
            next
          end
        end
      ensure
        Thread.current[:lit_cache_keys] = nil
      end
      
      @cache.lit_logger.info "Completed loading all YAML translations into cache"
    end

    def scan_for_new_yaml_translations
      new_translations = []
      
      yaml_files = I18n.load_path.select { |path| path.end_with?('.yml') || path.end_with?('.yaml') }
      
      @cache.lit_logger.info "Scanning #{yaml_files.length} YAML files for new translations"
      
      yaml_files.each do |file_path|
        next unless File.exist?(file_path)
        
        begin
          yaml_content = YAML.load_file(file_path, aliases: true)
        rescue => e
          begin
            yaml_content = YAML.load_file(file_path)
          rescue => e2
            @cache.lit_logger.warn "Failed to scan YAML file #{file_path}: #{e2.message}"
            next
          end
        end
        
        next unless yaml_content.is_a?(Hash)
        
        yaml_content.each do |locale, translations|
          next unless valid_locale?(locale)
          
          begin
            flattened = flatten_yaml_translations(translations)
            flattened.each do |key, value|
              unless translation_exists_in_database?(locale, key)
                new_translations << {
                  file: file_path,
                  locale: locale,
                  key: key,
                  value: value,
                  is_array: value.is_a?(Array)
                }
              end
            end
          rescue => e
            @cache.lit_logger.warn "Failed to process translations in #{file_path} for locale #{locale}: #{e.message}"
            next
          end
        end
      end
      
      new_translations
    end

    def store_new_translations_with_store_item(new_translations)
      return if new_translations.empty?
      
      @cache.lit_logger.info "Storing #{new_translations.length} new translations using store_item method"
      
      batch_size = 500
      new_translations.each_slice(batch_size).with_index do |batch, batch_index|
        batch_num = batch_index + 1
        total_batches = (new_translations.length / batch_size.to_f).ceil
        
        @cache.lit_logger.info "Storing new translations batch #{batch_num}/#{total_batches} (#{batch.length} translations)"
        
        begin
          ActiveRecord::Base.transaction do
            batch.each do |translation|
              locale = translation[:locale]
              key = translation[:key]
              value = translation[:value]
              
              store_item(locale, { key => value }, [], false)
            end
          end
        rescue => e
          @cache.lit_logger.error "Failed to store new translations batch #{batch_num}: #{e.message}"
          @cache.lit_logger.error e.backtrace.join("\n") if Rails.env.development?
          next
        end
      end
      
      @cache.lit_logger.info "Completed storing new translations"
    end

    def translation_exists_in_database?(locale, key)
      localization_key = Lit::LocalizationKey.find_by(localization_key: key)
      return false unless localization_key
      
      Lit::Localization.exists?(
        localization_key: localization_key,
        locale: Lit::Locale.find_by(locale: locale)
      )
    end

    def flatten_yaml_translations(translations, prefix = '')
      result = {}
      
      translations.each do |key, value|
        full_key = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
        
        if value.is_a?(Hash)
          result.merge!(flatten_yaml_translations(value, full_key))
        else
          result[full_key] = value
        end
      end
      
      result
    end

    def flatten_translations_for_batching(locale, data, scope, result)
      if data.respond_to?(:to_hash)
        data.to_hash.each do |k, value|
          flatten_translations_for_batching(locale, value, scope + [k], result)
        end
      elsif data.respond_to?(:to_str) || data.is_a?(Array)
        key = scope.join('.')
        result << [locale, key, data, data.is_a?(Array)]
      end
    end

    def values_equal?(value1, value2)
      # Handle nil cases
      return true if value1.nil? && value2.nil?
      return false if value1.nil? || value2.nil?
      
      # Both are arrays - compare arrays
      if value1.is_a?(Array) && value2.is_a?(Array)
        return value1 == value2
      end
      
      # One is array, one is not - not equal
      return false if value1.is_a?(Array) || value2.is_a?(Array)
      
      # Both are strings or can be compared directly
      value1.to_s == value2.to_s
    end

    def load_translations_to_cache
      Thread.current[:lit_cache_keys] = @cache.keys
      ActiveRecord::Base.transaction do
        (@translations || {}).each do |locale, data|
          store_item(locale, data, [], true) if valid_locale?(locale)
        end
      end
      Thread.current[:lit_cache_keys] = nil
    end

    private

    def on_rails_6_1_or_higher?
      "#{::Rails::VERSION::MAJOR}#{::Rails::VERSION::MINOR}".to_i == 61 ||
        ::Rails::VERSION::MAJOR >= 7
    end

    def update_default_localization(locale, options)
      parts = I18n.normalize_keys(locale, @untranslated_key, options[:scope], options[:separator])
      key_with_locale = parts.join('.')
      content = options[:lit_default_copy]
      # we do not force array on singular strings packed into Array
      @cache.update_locale(key_with_locale, content, content.is_a?(Array) && content.length > 1)
    end

    def can_dup_default(options = {})
      return false unless options.key?(:default)
      return true if options[:default].is_a?(String)
      return true if options[:default].is_a?(Array) && \
                     (options[:default].first.is_a?(String) || \
                      options[:default].first.is_a?(Symbol) || \
                      options[:default].first.is_a?(Array))
      false
    end

    def lookup(locale, key, scope = [], options = {})
      init_translations unless initialized?

      parts = I18n.normalize_keys(locale, key, scope, options[:separator])
      key_with_locale = parts.join('.')

      # we might want to return content later, but we first need to check if it's in cache.
      # it's important to rememver, that accessing non-existen key modifies cache by creating one
      had_key = @cache.has_key?(key_with_locale)

      # check in cache or in simple backend
      content = @cache[key_with_locale] || super

      # return if content is in cache - it CAN be `nil`
      return content if had_key && !options[:default]

      return content if parts.size <= 1

      if content.nil? && should_cache?(key_with_locale, options, had_key)
        new_content = @cache.init_key_with_value(key_with_locale, content)
        content = new_content if content.nil? # Content can change when Lit.humanize is true for example
        # so there is no content in cache - it might not be if ie. we're doing
        # fallback to already existing language
        if content.nil?
          # check if default was provided
          if options[:lit_default_copy].present?
            # default most likely will be an array
            if options[:lit_default_copy].is_a?(Array)
              default = options[:lit_default_copy].map do |key_or_value|
                if key_or_value.is_a?(Symbol)
                  normalized = I18n.normalize_keys(
                    nil, key_or_value.to_s, options[:scope], options[:separator]
                  ).join('.')
                  if on_rails_6_1_or_higher? && Lit::Services::HumanizeService.should_humanize?(key)
                    Lit::Services::HumanizeService.humanize(normalized)
                  else
                    normalized.to_sym
                  end
                else
                  key_or_value
                end
              end
            else
              default = options[:lit_default_copy]
            end
            content = default
          end
          # if we have content now, let's store it in cache
          if content.present?
            content = Array.wrap(content).compact.reject(&:empty?).reverse.find do |default_cand|
              @cache[key_with_locale] = default_cand
              @cache[key_with_locale]
            end
          end

          if content.nil? && !on_rails_6_1_or_higher? && Lit::Services::HumanizeService.should_humanize?(key)
            @cache[key_with_locale] = Lit::Services::HumanizeService.humanize(key)
            content = @cache[key_with_locale]
          end
        end
      end
      # return translated content
      content
    end

    def store_item(locale, data, scope = [], startup_process = false)
      key = ([locale] + scope).join('.')
      if data.respond_to?(:to_hash)
        # ActiveRecord::Base.transaction do
          data.to_hash.each do |k, value|
            store_item(locale, value, scope + [k], startup_process)
          end
        # end
      elsif data.respond_to?(:to_str) || data.is_a?(Array)
        key = ([locale] + scope).join('.')
        return if startup_process && Lit.ignore_yaml_on_startup && (Thread.current[:lit_cache_keys] || @cache.keys).member?(key)
        @cache.update_locale(key, data, data.is_a?(Array), startup_process)
      elsif data.nil?
        return if startup_process
        key = ([locale] + scope).join('.')
        @cache.delete_locale(key)
      end
    end

    def init_translations
      # Load all translations from *.yml, *.rb files to @translations variable.
      # We don't want to store translations in lit cache just yet. We'll do it
      # with `load_translations_to_cache` when all translations form yml (rb)
      # files will be loaded.
      without_store_items { load_translations }
      # load translations from database to cache
      @cache.load_all_translations
      # load translations from @translations to cache in batches
      load_yaml_translations_in_batches unless Lit.ignore_yaml_on_startup
      @initialized = true
    end

    def without_store_items
      @store_items = false
      yield
    ensure
      @store_items = true
    end

    def store_items?
      !instance_variable_defined?(:@store_items) || @store_items
    end

    def valid_locale?(locale)
      @locales ||= ::Rails.configuration.i18n.available_locales
      !@locales || @locales.map(&:to_s).include?(locale.to_s)
    end

    def is_ignored_key(key_without_locale)
      Lit.ignored_keys.any?{ |k| key_without_locale.start_with?(k) }
    end

    # checks if should cache. `had_key` is passed, as once cache has been accesed, it's already modified and key exists
    def should_cache?(key_with_locale, options, had_key)
      if had_key
        return false unless options[:default] && !options[:default].is_a?(Array)
      end

      _, key_without_locale = ::Lit::Cache.split_key(key_with_locale)
      return false if is_ignored_key(key_without_locale)

      true
    end
  end
end

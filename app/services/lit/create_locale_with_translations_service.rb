module Lit
  class CreateLocaleWithTranslationsService
    def initialize(locale_code)
      @locale_code = locale_code.to_s.downcase
      @cache_updater = ::Lit::CacheUpdater.new(::Lit.init.cache)
    end

    def call
      validate_translation_provider!
      en_locale = find_en_locale
      new_locale = create_locale

      new_locale.update_column(:is_hidden, false) if new_locale.is_hidden?
      reset_locale_cache

      result = process_translations(new_locale, en_locale)

      {
        success: true,
        translated_count: result[:translated_count],
        error_count: result[:error_count],
        locale: new_locale
      }
    rescue ::ArgumentError, ::ActiveRecord::RecordInvalid => e
      { success: false, error: e.message }
    rescue => e
      { success: false, error: e.message }
    end

    private

    def validate_translation_provider!
      return if ::Lit::CloudTranslation&.provider

      raise ::ArgumentError, 'Google Translation is not configured'
    end

    def find_en_locale
      en_locale = ::Lit::EnLocalizationFinder.find_en_locale
      raise ::ArgumentError, 'English locale not found' unless en_locale
      en_locale
    end

    def create_locale
      ::Lit::LocaleCreator.new(@locale_code).call
    end

    def reset_locale_cache
      return unless ::I18n.backend.respond_to?(:reset_available_locales_cache)
      ::I18n.backend.reset_available_locales_cache
    end

    def process_translations(new_locale, en_locale)
      en_localizations = get_en_localizations(en_locale)
      translation_processor = get_translation_processor

      translated_count = 0
      error_count = 0
      seen_errors = ::Set.new

      en_localizations.find_each do |en_localization|
        result = process_single_localization(
          en_localization,
          new_locale,
          translation_processor,
          seen_errors
        )

        if result[:success]
          translated_count += 1
        else
          error_count += 1
        end
      end

      { translated_count: translated_count, error_count: error_count }
    end

    def get_en_localizations(en_locale)
      finder = ::Lit::EnLocalizationFinder.new(en_locale)
      finder.find_all
    end

    def get_translation_processor
      ::Lit::TranslationProcessor.new(::Lit::CloudTranslation.provider)
    end

    def process_single_localization(en_localization, new_locale, translation_processor, seen_errors)
      en_value = extract_value(en_localization)
      return { success: false, reason: 'blank_value' } if en_value.blank?

      localization_key = en_localization.localization_key

      translated_value = begin
        translate_value(
          en_value,
          translation_processor
        )
      rescue => e
        log_translation_error(en_localization, e, seen_errors)
        en_value
      end

      begin
        create_localization_record(
          new_locale,
          localization_key,
          translated_value
        )
        { success: true }
      rescue => e
        log_creation_error(e, seen_errors)
        { success: false, reason: 'creation_error' }
      end
    end

    def extract_value(localization)
      localization.translation || localization.default_value
    end

    def translate_value(value, translation_processor)
      translation_processor.translate(
        value,
        from: 'en',
        to: @locale_code
      )
    end

    def create_localization_record(locale, localization_key, translated_value)
      creator = ::Lit::LocalizationCreator.new(
        locale,
        localization_key,
        translated_value
      )

      new_localization = creator.call
      return unless new_localization

      @cache_updater.update(
        @locale_code,
        localization_key.localization_key,
        translated_value
      )
    end

    def log_translation_error(localization, error, seen_errors)
      error_key = "translation:#{error.message}"
      return if seen_errors.include?(error_key)
      
      seen_errors.add(error_key)
      ::Rails.logger.warn(
        "Failed to translate key #{localization.localization_key.localization_key}: #{error.message}"
      )
    end

    def log_creation_error(error, seen_errors)
      error_key = "creation:#{error.message}"
      return if seen_errors.include?(error_key)
      
      seen_errors.add(error_key)
      ::Rails.logger.error("Error creating localization: #{error.class} - #{error.message}")
      ::Rails.logger.error("  Backtrace: #{error.backtrace.first(10).join("\n")}")
    end
  end
end

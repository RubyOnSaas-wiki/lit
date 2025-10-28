module Lit
  class ExportService
    def initialize(locale)
      @locale = locale
    end

    def generate_yaml
      translations_hash = build_translations_hash
      yaml_content = translations_hash.to_yaml
      
      header = generate_header
      
      header + yaml_content
    end

    def translation_count
      @translation_count ||= localizations.count
    end

    private

    def localizations
      @localizations ||= Lit::Localization.active
                                         .joins(:localization_key)
                                         .where(locale_id: @locale.id)
                                         .includes(:localization_key)
                                         .order('lit_localization_keys.localization_key ASC')
    end

    def build_translations_hash
      translations_hash = {}
      
      localizations.each do |localization|
        begin
          localization_key = localization.localization_key.localization_key
          
          next if localization_key.blank?
          
          key_parts = localization_key.split('.')
          
          if key_parts.length == 1
            translations_hash[key_parts.first] = localization.translation
            next
          end
          
          current_hash = translations_hash
          
          key_parts[0..-2].each do |part|
            current_hash[part] ||= {}
            current_hash = current_hash[part]
          end
          
          current_hash[key_parts.last] = localization.translation
        rescue => e
          next
        end
      end

      translations_hash
    end

    def generate_header
      "# #{@locale.locale.upcase} translations\n" \
      "# Generated on #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}\n" \
      "# Total translations: #{translation_count}\n" \
      "# Only active (non-deleted) translations are included\n\n"
    end
  end
end
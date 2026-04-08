module Lit
  class LocalizationCreator
    def initialize(locale, localization_key, translated_value)
      @locale = locale
      @localization_key = localization_key
      @translated_value = normalize_for_yaml_serialization(translated_value)
    end

    def call
      return nil if localization_exists?

      create_localization
    end

    private

    def localization_exists?
      ::Lit::Localization.exists?(
        locale_id: @locale.id,
        localization_key_id: @localization_key.id
      )
    end

    def normalize_for_yaml_serialization(value)
      return nil if value.nil?
      
      case value
      when ::String, ::Numeric, ::TrueClass, ::FalseClass, ::NilClass
        value
      when ::Array
        value.map { |item| normalize_for_yaml_serialization(item) }
      when ::Hash
        value.transform_values { |v| normalize_for_yaml_serialization(v) }
      else
        value.to_s
      end
    end

    def create_localization
      safe_value = ensure_basic_type(@translated_value)
      
      localization = ::Lit::Localization.new(
        locale: @locale,
        localization_key: @localization_key,
        is_changed: true
      )
      
      localization.default_value = safe_value
      localization.translated_value = safe_value
      localization.save!
      
      localization
    end

    def ensure_basic_type(value)
      case value
      when ::String, ::Numeric, ::TrueClass, ::FalseClass, ::NilClass
        value
      when ::Array
        value.map { |item| ensure_basic_type(item) }
      when ::Hash
        value.each_with_object({}) do |(k, v), h|
          h[k.to_s] = ensure_basic_type(v)
        end
      else
        value.to_s
      end
    end
  end
end

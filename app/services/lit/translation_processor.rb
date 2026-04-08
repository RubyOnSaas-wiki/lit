module Lit
  class TranslationProcessor
    def initialize(translation_provider_module)
      @translation_provider_module = translation_provider_module
    end

    def translate(value, from:, to:)
      return value if value.blank?

      case value
      when ::Array
        translate_array(value, from: from, to: to)
      when ::String
        translate_string(value, from: from, to: to)
      else
        value
      end
    end

    private

    def translate_array(array, from:, to:)
      array.map do |item|
        if item.is_a?(::String) && !item.blank?
          translate_string(item, from: from, to: to)
        else
          item
        end
      end
    end

    def translate_string(text, from:, to:)
      result = @translation_provider_module.translate(text: text, from: from, to: to)
      result.is_a?(::String) ? result : result.to_s
    end
  end
end

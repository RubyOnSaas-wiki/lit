module Lit
  class LocaleCreator
    def initialize(locale_code)
      @locale_code = locale_code.to_s.downcase
    end

    def call
      validate!
      create_locale
    end

    private

    def validate!
      raise ::ArgumentError, "Language code cannot be blank" if @locale_code.blank?
      raise ::ArgumentError, "Language '#{@locale_code}' already exists" if locale_exists?
    end

    def locale_exists?
      ::Lit::Locale.exists?(locale: @locale_code)
    end

    def create_locale
      ::Lit::Locale.create!(locale: @locale_code)
    end
  end
end

module Lit
  class EnLocalizationFinder
    EN_CODE = 'en'

    def initialize(en_locale)
      @en_locale = en_locale
    end

    def find_all
      ::Lit::Localization.active
                      .joins(:localization_key)
                      .where(locale_id: @en_locale.id)
                      .includes(:localization_key)
    end

    def self.find_en_locale
      ::Lit::Locale.find_by(locale: EN_CODE)
    end
  end
end

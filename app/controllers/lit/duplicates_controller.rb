require_dependency 'lit/application_controller'

module Lit
  class DuplicatesController < ::Lit::ApplicationController
    def index
      @duplicates = find_duplicate_localization_keys
    end

    private

    def find_duplicate_localization_keys
      english_locale = Lit::Locale.find_by(locale: 'en')
      return {} unless english_locale

      keys = Hash.new { |h, k| h[k] = [] }
      
      Lit::LocalizationKey.active
                          .includes(:localizations)
                          .joins(:localizations)
                          .where(lit_localizations: { locale_id: english_locale.id })
                          .find_each do |key|
        english_localization = key.localizations.find { |l| l.locale_id == english_locale.id }
        translation = english_localization&.translation || ''

        keys[translation] << key.localization_key
      end

      duplicates = keys.select { |_translation, localization_keys| localization_keys.length > 1 }
      duplicates.sort_by { |translation, _| translation.to_s }
    end
  end
end

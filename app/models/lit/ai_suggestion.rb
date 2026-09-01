module Lit
  # A translation proposed by an AI agent through the AI API. It has no effect
  # on the application until a human accepts it: the value lives here, never in
  # lit_localizations, so neither the export nor the environment sync sees it.
  class AiSuggestion < ActiveRecord::Base
    serialize :suggested_value
    serialize :base_value

    ## ASSOCIATIONS
    belongs_to :localization_key, class_name: 'Lit::LocalizationKey'
    belongs_to :locale, class_name: 'Lit::Locale'

    ## VALIDATIONS
    validates :localization_key, :locale, presence: true
    validates :locale_id, uniqueness: { scope: :localization_key_id }

    ## SCOPES
    scope :pending, lambda {
      joins(:localization_key)
        .where(Lit::LocalizationKey.table_name => { is_deleted: false })
    }
    scope :ordered, lambda {
      joins(:localization_key).order("#{Lit::LocalizationKey.table_name}.localization_key asc")
    }
    scope :for_locale, ->(locale) { where(locale_id: locale) }

    # Creates or updates the single proposal for this key and locale.
    # Returns [status, suggestion] where status is :created, :updated or
    # :kept_human_edit.
    def self.propose(localization_key:, locale:, value:, provider: nil)
      suggestion = find_or_initialize_by(localization_key_id: localization_key.id,
                                         locale_id: locale.id)
      return [:kept_human_edit, suggestion] if suggestion.persisted? && suggestion.is_edited?

      status = suggestion.new_record? ? :created : :updated
      suggestion.suggested_value = value
      suggestion.provider = provider
      suggestion.base_value = suggestion.current_value
      suggestion.save!
      [status, suggestion]
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    def full_key
      [locale.locale, localization_key.localization_key].join('.')
    end

    def localization
      localization_key.localizations.find_by(locale_id: locale_id)
    end

    # The value the application serves right now. Read from the same place the
    # Translate! list reads it, so editing a translation there is reflected here
    # immediately. Falls back to the record without creating one.
    def current_value
      cached = Lit.init.cache[full_key]
      return cached unless cached.nil?
      localization&.translation
    end

    # True when the translation changed after this proposal was recorded, i.e.
    # somebody translated the key by hand in the meantime.
    def stale?
      current_value != base_value
    end

    def accept
      localization = localization_key.localizations.find_or_initialize_by(locale_id: locale_id)
      localization.translated_value = suggested_value
      localization.is_changed = true
      localization.save!
      # Localization#update_cache only runs `on: :update`, so a freshly created
      # row would otherwise never reach the cache.
      Lit.init.cache.update_cache(localization.full_key, localization.translation)
      destroy
    end
  end
end

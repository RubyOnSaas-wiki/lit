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
    scope :corrections, -> { where(is_correction: true) }
    scope :new_translations, -> { where(is_correction: false) }

    # The locale translations are made from. A value in another locale that is
    # still the source text has not been translated yet.
    SOURCE_LOCALE = 'en'.freeze

    # Creates or updates the single proposal for this key and locale.
    # Returns [status, suggestion] where status is :created, :updated,
    # :kept_human_edit, or :unchanged when the value is what the application
    # already serves (nothing is stored then).
    def self.propose(localization_key:, locale:, value:, provider: nil)
      suggestion = find_or_initialize_by(localization_key_id: localization_key.id,
                                         locale_id: locale.id)
      return [:kept_human_edit, suggestion] if suggestion.persisted? && suggestion.is_edited?

      current = suggestion.current_value
      return [:unchanged, suggestion] if same_value?(value, current)

      status = suggestion.new_record? ? :created : :updated
      suggestion.suggested_value = value
      suggestion.provider = provider
      suggestion.base_value = current
      suggestion.is_correction = suggestion.existing_translation?
      suggestion.save!
      [status, suggestion]
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    # Where a locale's value stands: :missing, :same_as_source (still the
    # source text, so not translated yet) or :translated. Shared with the AI
    # API's lookup, so the agent sees the same split as the tab.
    def self.translation_status(locale_code, value, source_value)
      return :missing if value.blank?
      return :same_as_source if locale_code.to_s != SOURCE_LOCALE && same_value?(value, source_value)
      :translated
    end

    # Surrounding whitespace is not a different translation.
    def self.same_value?(one, other)
      normalize_value(one) == normalize_value(other)
    end

    def self.normalize_value(value)
      case value
      when String then value.strip
      when Array then value.map { |item| normalize_value(item) }
      else value
      end
    end

    # Sorts every pending proposal against what the application serves now and
    # drops the ones that would change nothing. Proposals recorded before
    # is_correction existed all read as new until this runs; it is safe to run
    # again at any time. A proposal a human edited is never dropped.
    def self.reclassify_all
      result = { new: 0, corrected: 0, removed_unchanged: 0 }
      includes(:locale, :localization_key).find_each do |suggestion|
        if !suggestion.is_edited? && same_value?(suggestion.suggested_value, suggestion.current_value)
          suggestion.destroy
          result[:removed_unchanged] += 1
        else
          suggestion.update_column(:is_correction, suggestion.existing_translation?)
          result[suggestion.is_correction? ? :corrected : :new] += 1
        end
      end
      result
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

    def source_value
      cached = Lit.init.cache["#{SOURCE_LOCALE}.#{localization_key.localization_key}"]
      return cached unless cached.nil?
      source = Lit::Locale.find_by(locale: SOURCE_LOCALE)
      source && localization_key.localizations.find_by(locale_id: source.id)&.translation
    end

    # True when the key already has a translation in this locale, so accepting
    # replaces somebody's wording instead of filling a gap.
    def existing_translation?
      self.class.translation_status(locale.locale, current_value, source_value) == :translated
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

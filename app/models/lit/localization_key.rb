module Lit
  class LocalizationKey < Lit::Base
    attr_accessor :interpolated_key

    # Keys Rails and state_machines try on the way to a more general text or a
    # humanized name. Lit keeps a row for each because it was looked up, not
    # because anybody has a text for it.
    RAILS_LOOKUP_PREFIXES = %w[
      activerecord.errors.
      activemodel.errors.
      errors.attributes.
      activerecord.attributes.
      activemodel.attributes.
      attributes.
      activerecord.models.
      activerecord.state_machines.
      helpers.label.
    ].freeze

    ## SCOPES
    scope :completed, -> { where(is_completed: true) }
    scope :not_completed, -> { where(is_completed: false) }
    scope :starred, -> { where(is_starred: true) }
    scope :ordered, -> { order(localization_key: :asc) }
    scope :active, -> { where(is_deleted: false) }
    scope :not_active, -> { where(is_deleted: true) }
    scope :visited_again, -> { where(is_visited_again: true) }
    scope :empty_rails_lookups, lambda {
      key = arel_table[:localization_key]
      # rows without a key exist, and a NULL inside NOT IN would match nothing
      with_text = Lit::Localization.where.not(localization_key_id: nil)
                                   .where('default_value IS NOT NULL OR translated_value IS NOT NULL')
      where(RAILS_LOOKUP_PREFIXES.map { |prefix| key.matches("#{prefix}%") }.reduce(:or))
        .where.not(id: with_text.select(:localization_key_id))
    }
    scope :after, lambda { |dt|
      joins(:localizations)
        .where('lit_localization_keys.updated_at >= ?', dt)
        .where('lit_localizations.is_changed = true')
    }

    ## ASSOCIATIONS
    has_many :localizations, dependent: :destroy
    has_many :localization_key_tags, dependent: :delete_all
    has_many :tags, through: :localization_key_tags
    has_many :ai_suggestions, class_name: 'Lit::AiSuggestion', dependent: :destroy

    ## VALIDATIONS
    validates :localization_key,
              presence: true,
              uniqueness: true

    ## ACCESSORS
    unless defined?(::ActionController::StrongParameters)
      attr_accessible :localization_key
    end

    ## BEFORE AND AFTER
    after_commit :check_completed, on: :update
    after_commit :remove_from_cache, on: :destroy

    def self.find_or_create_by_localization_key(localization_key)
      find_or_create_by(localization_key: localization_key) do |lk|
        lk.localization_key = localization_key
      end
    rescue ActiveRecord::RecordNotUnique
      find_by(localization_key: localization_key)
    end

    def to_s
      localization_key
    end

    def clone_localizations
      new_created = false
      Lit::Locale.find_each do |locale|
        localizations.where(locale_id: locale.id).first_or_create do |l|
          l.default_value = interpolated_key
          new_created = true
        end
      end
      return unless new_created
      Lit::LocalizationKey.update_all ['is_completed=?', false],
                                      ['id=? and is_completed=?', id, false]
    end

    def self.order_options
      ['localization_key asc', 'localization_key desc', 'created_at asc',
       'created_at desc', 'updated_at asc', 'updated_at desc']
    end

    # it can be overridden in parent application,
    # for example: {:order => "created_at desc"}
    def self.default_search_options
      {}
    end

    def self.search(options = {})
      LocalizationKeySearchQuery.new(self, options).perform
    end

    # The environment sync selects rows by updated_at, and update_all does not
    # set it, so it is set here or the rows would never be sent.
    def change_all_completed
      toggle_all_completed(updated_at: Time.current)
    end

    def soft_destroy
      ActiveRecord::Base.transaction do
        update is_deleted: true
        toggle_all_completed
        remove_from_cache
      end
    end

    def remove_from_cache
      Lit::Locale.pluck(:locale).each do |l|
        Lit.init.cache.delete_key "#{l}.#{localization_key}"
      end
    end

    def restore
      ActiveRecord::Base.transaction do
        update is_deleted: false, is_completed: false, is_visited_again: false
        localizations.update_all is_changed: false
      end
    end

    private

    def toggle_all_completed(row_attributes = {})
      self.class.transaction do
        toggle(:is_completed).save!
        localizations.update_all({ is_changed: is_completed }.merge(row_attributes))
      end
    end

    def check_completed
      self.is_completed = localizations.changed.count == localizations.count
      save! if is_completed_changed?
    end

    def lit_attribute_will_change
      localization_key_will_change!
    end
  end
end

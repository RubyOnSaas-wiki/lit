module Lit
  # A feature name recorded alongside a localization key, so that translations
  # introduced for one piece of work can be found together later.
  class Tag < ActiveRecord::Base
    ## ASSOCIATIONS
    has_many :localization_key_tags, dependent: :delete_all
    has_many :localization_keys, through: :localization_key_tags

    ## VALIDATIONS
    validates :name, presence: true, uniqueness: true

    ## SCOPES
    scope :ordered, -> { order(:name) }

    ## BEFORE & AFTER
    before_validation :normalize_name

    def self.normalize(name)
      name.to_s.strip.downcase
    end

    def self.find_or_create_normalized(name)
      normalized = normalize(name)
      return if normalized.blank?
      find_or_create_by(name: normalized)
    rescue ActiveRecord::RecordNotUnique
      find_by(name: normalized)
    end

    def to_s
      name
    end

    private

    def normalize_name
      self.name = self.class.normalize(name)
    end
  end
end

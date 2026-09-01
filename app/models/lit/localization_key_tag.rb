module Lit
  # Join model between Lit::LocalizationKey and Lit::Tag. It is an explicit
  # model rather than a `has_and_belongs_to_many` because Rails would derive the
  # join table name as `lit_localization_keys_tags`, and because the tag filter
  # queries this table directly.
  class LocalizationKeyTag < ActiveRecord::Base
    self.table_name = 'lit_localization_key_tags'

    ## ASSOCIATIONS
    belongs_to :localization_key, class_name: 'Lit::LocalizationKey'
    belongs_to :tag, class_name: 'Lit::Tag'

    ## VALIDATIONS
    validates :tag_id, uniqueness: { scope: :localization_key_id }
  end
end

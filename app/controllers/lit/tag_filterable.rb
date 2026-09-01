module Lit
  # Shared tag-filter plumbing for the localization key lists and the AI
  # suggestions tab. Including controllers must provide #tag_options_key_scope,
  # a Lit::LocalizationKey relation narrowed by everything EXCEPT the tag
  # filter.
  module TagFilterable
    extend ActiveSupport::Concern

    included do
      helper_method :tag_filter_options, :selected_tag_names
    end

    def selected_tag_names
      self.class.tag_names_from(@search_options && @search_options[:tags])
    end

    # Tags present in the current tab, plus whatever is selected right now.
    # Without the union, selecting one tag would hide every tag it does not
    # co-occur with and OR-ing in a second one would be impossible.
    def tag_filter_options
      @_tag_filter_options ||=
        begin
          # `reorder(nil)` is required, not cosmetic: the scope carries both
          # `distinct` and an ORDER BY, and PostgreSQL rejects
          # `SELECT DISTINCT id ... ORDER BY localization_key` in a subquery.
          key_ids = tag_options_key_scope.reorder(nil).unscope(:limit, :offset).select(:id)
          tag_ids = Lit::LocalizationKeyTag.where(localization_key_id: key_ids)
                                           .distinct.select(:tag_id)
          Lit::Tag.where(id: tag_ids)
                  .or(Lit::Tag.where(name: selected_tag_names))
                  .ordered
        end
    end

    class_methods do
      def tag_names_from(value)
        Array(value).map { |name| Lit::Tag.normalize(name) }.reject(&:blank?)
      end
    end
  end
end

# Filters pending AI suggestions. Used both by the AI translated tab and by
# Lit::AcceptAiSuggestionsJob, so "accept all" acts on exactly what the user was
# looking at.
class AiSuggestionSearchQuery
  def initialize(params = {})
    @params = (params || {}).to_h.with_indifferent_access
  end

  def perform
    scope = Lit::AiSuggestion.where(localization_key_id: key_ids)
    scope = scope.where(locale_id: locale_ids) if locale_filter.present?
    scope
  end

  # The localization keys behind the suggestions, ignoring the tag filter --
  # this is what the tag multiselect offers as options.
  def tag_options_key_scope
    Lit::LocalizationKey.active.where(id: untagged_suggestion_key_ids)
  end

  private

  def key_ids
    scope = Lit::LocalizationKey.active.where(id: suggestion_key_ids)
    return scope.select(:id) if tag_names.empty?
    scope.joins(:tags).where(Lit::Tag.table_name => { name: tag_names }).distinct.select(:id)
  end

  def suggestion_key_ids
    scope = Lit::AiSuggestion.all
    scope = scope.where(locale_id: locale_ids) if locale_filter.present?
    scope.select(:localization_key_id)
  end
  alias untagged_suggestion_key_ids suggestion_key_ids

  def tag_names
    @tag_names ||= Array(@params[:tags]).map { |name| Lit::Tag.normalize(name) }.reject(&:blank?)
  end

  def locale_filter
    @params[:locale]
  end

  def locale_ids
    Lit::Locale.where(locale: locale_filter.to_s).select(:id)
  end
end

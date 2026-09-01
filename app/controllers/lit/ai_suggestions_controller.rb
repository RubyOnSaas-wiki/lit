require_dependency 'lit/application_controller'

module Lit
  # The "AI translated" tab. Nothing here affects the running application until
  # a human accepts a suggestion.
  class AiSuggestionsController < ::Lit::ApplicationController
    include Lit::TagFilterable

    before_action :find_search_options
    before_action :find_ai_suggestion, only: %i[accept destroy update]

    def index
      @ai_suggestions = paginate(ordered_scope)
    end

    def accept
      @ai_suggestion.accept
      respond_to do |format|
        format.html { redirect_back_or_default(fallback_location: filtered_path) }
        format.js
      end
    end

    def update
      @ai_suggestion.update(suggested_value: params.require(:ai_suggestion)[:suggested_value],
                            is_edited: true)
      respond_to do |format|
        format.html { redirect_back_or_default(fallback_location: filtered_path) }
        format.js
      end
    end

    def destroy
      @ai_suggestion.destroy
      respond_to do |format|
        format.html { redirect_back_or_default(fallback_location: filtered_path) }
        format.js
      end
    end

    # Accepting can span thousands of rows, each costing several statements and
    # a cache write, so it never runs inside the request.
    def accept_all
      @accepted_count = @scope.count
      Lit::AcceptAiSuggestionsJob.perform_later(@search_options.to_hash) if @accepted_count.positive?
      redirect_to filtered_path,
                  notice: "Accepting #{@accepted_count} proposals in the background."
    end

    def reject_all
      @scope.destroy_all
      redirect_to filtered_path
    end

    private

    def find_search_options
      @search_options =
        if params.respond_to?(:permit)
          params.permit(:locale, :tags, tags: [])
        else
          params.slice('locale', 'tags')
        end
      @query = AiSuggestionSearchQuery.new(@search_options)
      @scope = @query.perform
    end

    def tag_options_key_scope
      @query.tag_options_key_scope
    end

    def ordered_scope
      @scope.includes(:locale, localization_key: :tags)
            .joins(:localization_key)
            .order("#{Lit::LocalizationKey.table_name}.localization_key asc",
                   "#{Lit::AiSuggestion.table_name}.locale_id asc")
    end

    def paginate(scope)
      if defined?(Kaminari) && scope.respond_to?(Kaminari.config.page_method_name)
        scope.send(Kaminari.config.page_method_name, params[:page])
      elsif defined?(WillPaginate) && scope.respond_to?(:paginate)
        scope.paginate(page: params[:page])
      else
        scope
      end
    end

    def find_ai_suggestion
      @ai_suggestion = Lit::AiSuggestion.find(params[:id].to_i)
    end

    def filtered_path
      ai_suggestions_path(@search_options.to_hash)
    end
  end
end

module Lit
  module ApplicationHelper
    # The AI tab is only offered once the migrations that back it have run, so
    # that upgrading the gem without migrating does not break every Lit page.
    def lit_ai_suggestions_available?
      return @_lit_ai_suggestions_available unless @_lit_ai_suggestions_available.nil?
      @_lit_ai_suggestions_available =
        begin
          Lit::AiSuggestion.table_exists? && Lit::Tag.table_exists?
        rescue ::ActiveRecord::ActiveRecordError
          false
        end
    end

    def lit_pending_ai_suggestions_count
      Lit::AiSuggestion.pending.count
    end
  end
end

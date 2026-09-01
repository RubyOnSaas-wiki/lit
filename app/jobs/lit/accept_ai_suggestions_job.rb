module Lit
  if defined?(::ActiveJob)
    # Accepts every pending suggestion matching a filter, in batches, so a large
    # "accept all" cannot exceed the request timeout or hold one long
    # transaction over thousands of rows.
    class AcceptAiSuggestionsJob < ::ActiveJob::Base
      BATCH_SIZE = 200

      queue_as :default

      def perform(filter = {})
        scope = AiSuggestionSearchQuery.new(filter).perform
        scope.in_batches(of: BATCH_SIZE) do |batch|
          ::ActiveRecord::Base.transaction do
            batch.each(&:accept)
          end
        end
      end
    end
  end
end

module Lit
  if defined?(::ActiveJob)
    class SynchronizeVisitedAtJob < ::ActiveJob::Base
      queue_as :default

      def perform(*_args)
        SynchronizeVisitedAtService.new.call
      end
    end
  end
end

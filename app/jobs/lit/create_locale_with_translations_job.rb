module Lit
  if defined?(::ActiveJob)
    class CreateLocaleWithTranslationsJob < ::ActiveJob::Base
      queue_as :default

      def perform(locale_code)
        service = CreateLocaleWithTranslationsService.new(locale_code)
        result = service.call

        return if result[:success]

        raise CreateLocaleWithTranslationsServiceError.new(result)
      end
    end
  end
end


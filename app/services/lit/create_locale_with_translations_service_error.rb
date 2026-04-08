module Lit
  class CreateLocaleWithTranslationsServiceError < StandardError
    attr_reader :result

    def initialize(result)
      @result = result
      super(result[:error] || 'Failed to create locale with translations')
    end
  end
end


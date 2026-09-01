module Lit
  module Api
    module V1
      module Ai
        # Token-authorized entry point for an AI translation agent. Deliberately
        # separate from Api::V1::BaseController: the environment sync key must
        # not grant write access to translation suggestions.
        class BaseController < ActionController::Base
          layout nil
          protect_from_forgery with: :null_session
          respond_to :json if ::Rails::VERSION::MAJOR < 5
          before_action :authenticate_ai_request!

          private

          def authenticate_ai_request!
            # Fail closed: a half-configured host must reject everyone rather
            # than accept an empty token.
            return head(:unauthorized) if Lit.ai_api_key.blank?

            authenticate_or_request_with_http_token do |token, _options|
              ActiveSupport::SecurityUtils.secure_compare(token.to_s, Lit.ai_api_key.to_s)
            end
          end
        end
      end
    end
  end
end

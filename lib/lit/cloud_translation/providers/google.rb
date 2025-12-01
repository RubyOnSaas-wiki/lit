# frozen_string_literal: true

require_relative 'base'
begin
  require 'google/cloud/translate/v3'
  require 'googleauth'
rescue LoadError
  raise StandardError, 'You need to add "gem \'google-cloud-translate\'" to your Gemfile to support Google Cloud Translation'
end

module Lit::CloudTranslation::Providers
  # Google Cloud Translation API provider for Lit translation suggestions.
  #
  # Configuration:
  #
  #   require 'lit/cloud_translation/providers/google'
  #
  #   Lit::CloudTranslation.provider = Lit::CloudTranslation::Providers::Google
  #
  #   # Service account configuration can be given via a file pointed to by
  #   # ENV['GOOGLE_TRANSLATE_API_KEYFILE'] (see here:
  #   # https://cloud.google.com/iam/docs/creating-managing-service-account-keys)
  #   #
  #   # Instead of providing the keyfile, credentials can be given using
  #   # GOOGLE_TRANSLATE_API_<element> environment variables, where e.g.
  #   # the GOOGLE_TRANSLATE_API_PROJECT_ID variable corresponds to the
  #   # `project_id` element of your credentials. Typically, only the following
  #   # variables are mandatory:
  #   # * GOOGLE_TRANSLATE_API_PROJECT_ID
  #   # * GOOGLE_TRANSLATE_API_PRIVATE_KEY_ID
  #   # * GOOGLE_TRANSLATE_API_PRIVATE_KEY (be sure that it contains correct line breaks)
  #   # * GOOGLE_TRANSLATE_API_CLIENT_EMAIL
  #   # * GOOGLE_TRANSLATE_API_CLIENT_ID
  #   #
  #   # Alternatively, the contents of that file can be given as a Ruby hash
  #   # and passed like the following (be careful to use secrets or something
  #   # that prevents exposing private credentials):
  #
  #   Lit::CloudTranslation.configure do |config|
  #     config.keyfile_hash = {
  #       'type' => 'service_account',
  #       'project_id' => 'foo',
  #       'private_key_id' => 'keyid',
  #       ... # see link above for reference
  #     }
  #   end
  class Google < Base
    def translate(text:, from: nil, to:, **opts)
      text_array = Array(sanitize_text(text))
      parent = "projects/#{config.keyfile_hash['project_id']}/locations/global"
      
      request = {
        parent: parent,
        contents: text_array,
        target_language_code: to.to_s
      }
      request[:source_language_code] = from.to_s if from
      
      response = client.translate_text(request)
      
      translations = response.translations.map(&:translated_text)
      unsanitize_text(text.is_a?(Array) ? translations : translations.first)
    rescue ::Google::Cloud::Error => e
      raise ::Lit::CloudTranslation::TranslationError, e.message, cause: e
    end

    private

    def client
      @client ||= begin
        credentials = ::Google::Auth::Credentials.new(config.keyfile_hash)
        ::Google::Cloud::Translate::V3::TranslationService::Client.new do |client_config|
          client_config.credentials = credentials
        end
      end
    end

    def default_config
      if ENV['GOOGLE_TRANSLATE_API_KEYFILE'].blank?
        env_keys = ENV.keys.grep(/\AGOOGLE_TRANSLATE_API_/)
        keyfile_keys = env_keys.map(&:downcase).map { |k| k.gsub('google_translate_api_', '') }
        keyfile_key_to_env_key_mapping = keyfile_keys.zip(env_keys).to_h
        return {
          keyfile_hash: keyfile_key_to_env_key_mapping.transform_values do |env_key|
            ENV[env_key]
          end
        }
      end
      { keyfile_hash: JSON.parse(File.read(ENV['GOOGLE_TRANSLATE_API_KEYFILE'])) }
    rescue JSON::ParserError
      raise
    rescue Errno::ENOENT
      { keyfile_hash: nil }
    end

    def require_config!
      return if config.keyfile_hash.present?
      raise 'GOOGLE_TRANSLATE_API_KEYFILE env or `config.keyfile_hash` not given'
    end

    def sanitize_text(text_or_array)
      case text_or_array
      when String
        text_or_array.gsub(/%{(.+?)}/, '<code>__LIT__\1__LIT__</code>').gsub(/\r\n/, '<code>0</code>')
      when Array
        text_or_array.map { |s| sanitize_text(s) }
      when nil
        ''
      else
        raise TypeError
      end
    end

    def unsanitize_text(text_or_array)
      case text_or_array
      when String
        text_or_array.gsub(%r{<code>0</code>}, "\r\n").gsub(%r{<code>__LIT__(.+?)__LIT__</code>}, '%{\1}')
      when Array
        text_or_array.map { |s| unsanitize_text(s) }
      else
        raise TypeError
      end
    end
  end
end

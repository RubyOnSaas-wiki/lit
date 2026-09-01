module Lit
  if defined?(::ActiveJob)
    # Imports keys newly added to the application's YAML locale files, so an AI
    # agent can work on fresh keys without waiting for the host's periodic run.
    # Never overwrites existing values.
    class RefreshKeysJob < ::ActiveJob::Base
      GUARD_KEY = 'lit:ai:refresh_keys:running'.freeze
      GUARD_TTL = 30 * 60 # seconds

      queue_as :default

      # Atomically claims the right to run. Returns false when a run is already
      # in flight, so a hammering client cannot launch parallel full scans.
      def self.claim_guard
        ::Rails.cache.write(GUARD_KEY, true, unless_exist: true, expires_in: GUARD_TTL)
      end

      def self.release_guard
        ::Rails.cache.delete(GUARD_KEY)
      end

      def perform
        backend = ::I18n.backend
        return unless backend.respond_to?(:init_translations_with_caching)
        backend.init_translations_with_caching
      ensure
        self.class.release_guard
      end
    end
  end
end

module Lit
  if defined?(::ActiveJob)
    # Imports keys newly added to the application's YAML locale files, so an AI
    # agent can work on fresh keys without waiting for the host's periodic run.
    # Never overwrites existing values.
    class RefreshKeysJob < ::ActiveJob::Base
      GUARD_KEY = 'lit:ai:refresh_keys:running'.freeze
      GUARD_TTL = 30 * 60 # seconds

      queue_as :default

      class << self
        # Atomically claims the right to run. Returns false when a run is
        # already in flight, so a hammering client cannot launch parallel full
        # scans of every YAML file.
        def claim_guard
          if (redis = guard_redis)
            # SET key 1 NX EX ttl is a single atomic claim. redis-rb >= 4
            # returns true/false, older versions return "OK"/nil.
            result = redis.set(guard_key, '1', nx: true, ex: GUARD_TTL)
            result == true || result == 'OK'
          else
            ::Rails.cache.write(GUARD_KEY, true, unless_exist: true, expires_in: GUARD_TTL)
          end
        end

        def release_guard
          if (redis = guard_redis)
            redis.del(guard_key)
          else
            ::Rails.cache.delete(GUARD_KEY)
          end
        end

        private

        # Prefer Lit's own key-value store: it is shared across processes and
        # hosts wherever Lit runs on Redis, whereas Rails.cache may legitimately
        # be a NullStore (elvium does exactly that in development), which would
        # make the guard silently never hold.
        def guard_redis
          return nil unless Lit.respond_to?(:redis)
          Lit.redis
        rescue StandardError
          nil
        end

        def guard_key
          prefix = Lit.storage_options.is_a?(Hash) ? Lit.storage_options[:prefix] : nil
          [prefix, GUARD_KEY].compact.join('-')
        end
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

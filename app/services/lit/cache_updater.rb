module Lit
  class CacheUpdater
    def initialize(cache)
      @cache = cache
    end

    def update(locale_code, localization_key, value)
      cache_key = "#{locale_code}.#{localization_key}"
      @cache.update_cache(cache_key, value)
    end
  end
end


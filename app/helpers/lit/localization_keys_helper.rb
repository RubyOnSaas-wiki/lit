module Lit
  module LocalizationKeysHelper
    include LocalizationsHelper

    # The cache only holds a key once the application has used it, so a row can
    # have a translation the cache does not know about yet.
    def served_value(locale, localization_key, localization)
      cached = Lit.init.cache["#{locale}.#{localization_key.localization_key}"]
      cached.nil? ? localization.translation : cached
    end
  end
end

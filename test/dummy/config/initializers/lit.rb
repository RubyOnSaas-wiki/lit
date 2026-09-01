Lit.authentication_function = :authenticate_admin!
Lit.authentication_verification = :admin_signed_in?
Lit.key_value_engine = ENV['LIT_STORAGE'] || 'redis'
Lit.humanize_key = false
Lit.ignore_yaml_on_startup = true
Lit.api_enabled = true
Lit.api_key = 'ala'
Lit.ai_api_enabled = true
Lit.ai_api_key = 'ai-ala'
Lit.all_translations_are_html_safe = true

# Rails 7+ forbids autoloading during initialization; the host app (elvium) does the
# same thing in an after_initialize block.
Rails.application.config.after_initialize { Lit.init }

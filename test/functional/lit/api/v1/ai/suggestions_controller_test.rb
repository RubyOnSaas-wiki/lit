require 'test_helper'

module Lit
  class Api::V1::Ai::SuggestionsControllerTest < ActionController::TestCase
    include ActiveJob::TestHelper

    def setup
      # The dummy app has no cache store configured; the refresh guard needs a
      # real one.
      ::Rails.cache = ActiveSupport::Cache::MemoryStore.new
      # the refresh guard lives in redis with a 30 minute TTL; without this the
      # refresh_keys tests depend on whether a previous run left it claimed
      Lit::RefreshKeysJob.release_guard
      Lit::AiSuggestion.delete_all
      Lit::LocalizationKeyTag.delete_all
      Lit::Tag.delete_all
      Lit::Localization.delete_all
      Lit::LocalizationKey.delete_all
      Lit.loader = nil

      Lit.api_enabled = true
      Lit.api_key = 'sync-key'
      Lit.ai_api_enabled = true
      Lit.ai_api_key = 'ai-key'
      reload_lit_routes

      @locale = Lit::Locale.where(locale: 'sv').first_or_create!
      Lit::Locale.where(locale: 'en').first_or_create!
      @key = Lit::LocalizationKey.create!(localization_key: 'hr.tree.title')
      authorize_with 'ai-key'
      Lit.init
    end

    def teardown
      Lit.ai_api_enabled = nil
      Lit.ai_api_key = nil
    end

    def reload_lit_routes
      Lit::Engine.routes.clear!
      Dummy::Application.reload_routes!
      @routes = Lit::Engine.routes
    end

    def authorize_with(token)
      request.env['HTTP_AUTHORIZATION'] =
        ActionController::HttpAuthentication::Token.encode_credentials(token)
    end

    def payload(overrides = {})
      { provider: 'claude-opus-5',
        suggestions: [{ key: 'hr.tree.title', locale: 'sv',
                        value: 'Organisationsträd', tags: ['HR-Tree'] }.merge(overrides)] }
    end

    # --- authorization -----------------------------------------------------

    test 'rejects a request with no token' do
      request.env.delete('HTTP_AUTHORIZATION')
      post :create, params: payload, as: :json
      assert_response :unauthorized
    end

    test 'rejects a wrong token' do
      authorize_with 'nope'
      post :create, params: payload, as: :json
      assert_response :unauthorized
    end

    test 'rejects the environment sync token' do
      authorize_with 'sync-key'
      post :create, params: payload, as: :json
      assert_response :unauthorized
      assert_equal 0, Lit::AiSuggestion.count
    end

    test 'fails closed when no ai api key is configured' do
      Lit.ai_api_key = nil
      authorize_with ''
      post :create, params: payload, as: :json
      assert_response :unauthorized
    end

    # --- create ------------------------------------------------------------

    test 'stores a suggestion without touching the translation' do
      post :create, params: payload, as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 1, body['created']
      suggestion = Lit::AiSuggestion.sole
      assert_equal 'Organisationsträd', suggestion.suggested_value
      assert_equal 'claude-opus-5', suggestion.provider
      assert_equal 0, Lit::Localization.where(locale_id: @locale.id).count
    end

    test 'attaches normalized tags to the localization key' do
      post :create, params: payload, as: :json

      assert_equal ['hr-tree'], @key.reload.tags.map(&:name)
    end

    test 'rejects an unknown key without creating anything' do
      post :create, params: payload(key: 'no.such.key'), as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal 0, body['created']
      assert_equal 'unknown_key', body['rejected'].first['reason']
      assert_equal 0, Lit::AiSuggestion.count
    end

    test 'rejects an unknown locale without creating anything' do
      post :create, params: payload(locale: 'zz'), as: :json

      body = JSON.parse(response.body)
      assert_equal 'unknown_locale', body['rejected'].first['reason']
      assert_equal 0, Lit::AiSuggestion.count
    end

    test 'upserts a second suggestion for the same key and locale' do
      post :create, params: payload, as: :json
      post :create, params: payload(value: 'Nytt förslag'), as: :json

      body = JSON.parse(response.body)
      assert_equal 1, body['updated']
      assert_equal 1, Lit::AiSuggestion.count
      assert_equal 'Nytt förslag', Lit::AiSuggestion.sole.suggested_value
    end

    test 'skips a suggestion a human has already edited' do
      post :create, params: payload, as: :json
      Lit::AiSuggestion.sole.update!(suggested_value: 'Handredigerad', is_edited: true)

      post :create, params: payload(value: 'Maskin igen'), as: :json

      body = JSON.parse(response.body)
      assert_equal 'kept_human_edit', body['skipped'].first['reason']
      assert_equal 'Handredigerad', Lit::AiSuggestion.sole.suggested_value
    end

    test 'skips a suggestion identical to the value already served' do
      Lit.init.cache.update_cache('sv.hr.tree.title', 'Organisationsträd')

      post :create, params: payload, as: :json

      body = JSON.parse(response.body)
      assert_equal 0, body['created']
      assert_equal 'unchanged', body['skipped'].first['reason']
      assert_equal 0, Lit::AiSuggestion.count
    end

    test 'counts the suggestions that correct an existing translation' do
      Lit.init.cache.update_cache('en.hr.tree.title', 'Organisation tree')
      Lit.init.cache.update_cache('sv.hr.tree.title', 'Organisationsschema')

      post :create, params: payload, as: :json

      body = JSON.parse(response.body)
      assert_equal 1, body['created']
      assert_equal 1, body['corrections']
      assert Lit::AiSuggestion.sole.is_correction
    end

    test 'refuses an oversized batch' do
      many = Array.new(501) { { key: 'hr.tree.title', locale: 'sv', value: 'x' } }
      post :create, params: { suggestions: many }, as: :json

      assert_response :payload_too_large
      assert_equal 0, Lit::AiSuggestion.count
    end

    # --- pending -----------------------------------------------------------

    test 'lists a key that has no localization row at all for the locale' do
      get :pending, params: { locale: 'sv' }, as: :json

      assert_response :success
      keys = JSON.parse(response.body)['keys'].map { |k| k['key'] }
      assert_includes keys, 'hr.tree.title'
    end

    test 'omits a key already translated in the target locale' do
      @key.localizations.create!(locale: @locale, translated_value: 'klar', is_changed: true)

      get :pending, params: { locale: 'sv' }, as: :json

      keys = JSON.parse(response.body)['keys'].map { |k| k['key'] }
      assert_not_includes keys, 'hr.tree.title'
    end

    test 'reports the source value and any pending suggestion' do
      Lit.init.cache.update_cache('en.hr.tree.title', 'Org tree')
      Lit::AiSuggestion.propose(localization_key: @key, locale: @locale, value: 'Förslag')

      get :pending, params: { locale: 'sv', source_locale: 'en' }, as: :json

      entry = JSON.parse(response.body)['keys'].find { |k| k['key'] == 'hr.tree.title' }
      assert_equal 'Org tree', entry['source_value']
      assert_equal 'Förslag', entry['existing_suggestion']
    end

    test 'filters pending keys by tag' do
      other = Lit::LocalizationKey.create!(localization_key: 'other.key')
      @key.tags << Lit::Tag.create!(name: 'hr-tree')

      get :pending, params: { locale: 'sv', tags: ['hr-tree'] }, as: :json

      keys = JSON.parse(response.body)['keys'].map { |k| k['key'] }
      assert_includes keys, @key.localization_key
      assert_not_includes keys, other.localization_key
    end

    test 'caps the page size' do
      600.times { |i| Lit::LocalizationKey.create!(localization_key: "bulk.key#{i}") }

      get :pending, params: { locale: 'sv', limit: 5000 }, as: :json

      assert_equal 500, JSON.parse(response.body)['keys'].size
    end

    test 'requires a locale' do
      get :pending, as: :json
      assert_response :bad_request
    end

    # --- lookup ------------------------------------------------------------

    def lookup_entry(body, key)
      body['keys'].find { |entry| entry['key'] == key }
    end

    test 'reports what each locale serves and whether it is translated' do
      Lit::Locale.where(locale: 'da').first_or_create!
      Lit.init.cache.update_cache('en.hr.tree.title', 'Organisation tree')
      Lit.init.cache.update_cache('sv.hr.tree.title', 'Organisationsschema')
      Lit.init.cache.update_cache('da.hr.tree.title', 'Organisation tree')

      post :lookup, params: { keys: ['hr.tree.title'] }, as: :json

      assert_response :success
      translations = lookup_entry(JSON.parse(response.body), 'hr.tree.title')['translations']
      assert_equal({ 'value' => 'Organisation tree', 'status' => 'translated', 'suggestion' => nil },
                   translations['en'])
      assert_equal 'translated', translations['sv']['status']
      assert_equal 'Organisationsschema', translations['sv']['value']
      assert_equal 'same_as_source', translations['da']['status']
    end

    test 'reports a locale with no value as missing' do
      post :lookup, params: { keys: ['hr.tree.title'], locales: ['sv'] }, as: :json

      translations = lookup_entry(JSON.parse(response.body), 'hr.tree.title')['translations']
      assert_equal ['sv'], translations.keys
      assert_equal 'missing', translations['sv']['status']
      assert_nil translations['sv']['value']
    end

    test 'includes a pending suggestion and the key tags' do
      @key.tags << Lit::Tag.create!(name: 'hr-tree')
      Lit::AiSuggestion.propose(localization_key: @key, locale: @locale, value: 'Förslag')

      post :lookup, params: { keys: ['hr.tree.title'] }, as: :json

      entry = lookup_entry(JSON.parse(response.body), 'hr.tree.title')
      assert_equal ['hr-tree'], entry['tags']
      assert_equal 'Förslag', entry['translations']['sv']['suggestion']
    end

    test 'lists keys Lit does not know separately' do
      post :lookup, params: { keys: ['hr.tree.title', 'no.such.key'] }, as: :json

      body = JSON.parse(response.body)
      assert_equal ['hr.tree.title'], body['keys'].map { |entry| entry['key'] }
      assert_equal ['no.such.key'], body['unknown_keys']
    end

    test 'looks up a whole namespace by prefix' do
      Lit::LocalizationKey.create!(localization_key: 'hr.tree.subtitle')
      Lit::LocalizationKey.create!(localization_key: 'hr.treehouse')
      Lit::LocalizationKey.create!(localization_key: 'billing.invoice')

      post :lookup, params: { prefix: 'hr.tree' }, as: :json

      body = JSON.parse(response.body)
      assert_equal %w[hr.tree.subtitle hr.tree.title], body['keys'].map { |entry| entry['key'] }
      assert_equal 2, body['total']
    end

    test 'pages a prefix lookup' do
      3.times { |i| Lit::LocalizationKey.create!(localization_key: "hr.tree.item#{i}") }

      post :lookup, params: { prefix: 'hr.tree', limit: 2, page: 2 }, as: :json

      body = JSON.parse(response.body)
      assert_equal %w[hr.tree.item2 hr.tree.title], body['keys'].map { |entry| entry['key'] }
      assert_equal 4, body['total']
    end

    test 'lookup needs either keys or a prefix' do
      post :lookup, params: {}, as: :json
      assert_response :bad_request

      post :lookup, params: { keys: ['hr.tree.title'], prefix: 'hr' }, as: :json
      assert_response :bad_request
    end

    test 'refuses a lookup of too many keys' do
      post :lookup, params: { keys: Array.new(501) { |i| "k#{i}" } }, as: :json
      assert_response :payload_too_large
    end

    test 'lookup requires the ai token' do
      authorize_with 'sync-key'
      post :lookup, params: { keys: ['hr.tree.title'] }, as: :json
      assert_response :unauthorized
    end

    # --- refresh_keys ------------------------------------------------------

    test 'enqueues the key refresh job' do
      assert_enqueued_with(job: Lit::RefreshKeysJob) do
        post :refresh_keys, as: :json
      end
      assert_response :accepted
    end

    test 'does not enqueue a second refresh while one is in flight' do
      post :refresh_keys, as: :json

      assert_no_enqueued_jobs(only: Lit::RefreshKeysJob) do
        post :refresh_keys, as: :json
      end
      assert_response :success
      assert_equal 'already_running', JSON.parse(response.body)['status']
    end
  end
end

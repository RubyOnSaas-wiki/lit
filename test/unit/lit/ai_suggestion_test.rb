require 'test_helper'

module Lit
  class AiSuggestionTest < ActiveSupport::TestCase
    setup do
      Lit.init
      @locale = Lit::Locale.where(locale: 'sv').first_or_create!
      @key = Lit::LocalizationKey.create!(localization_key: 'ai.suggestion.test')
    end

    def propose(value: 'Organisationsträd', provider: 'claude-opus-5')
      Lit::AiSuggestion.propose(localization_key: @key, locale: @locale,
                                value: value, provider: provider)
    end

    test 'accepting creates the localization when none exists for that locale' do
      assert_nil @key.localizations.find_by(locale_id: @locale.id)
      _status, suggestion = propose

      suggestion.accept

      localization = @key.localizations.find_by(locale_id: @locale.id)
      assert_not_nil localization
      assert_equal 'Organisationsträd', localization.translated_value
      assert localization.is_changed
      assert_equal 'Organisationsträd', Lit.init.cache["sv.#{@key.localization_key}"]
      assert_not Lit::AiSuggestion.exists?(suggestion.id)
    end

    test 'accepting overwrites an existing localization' do
      @key.localizations.create!(locale: @locale, translated_value: 'gammal', is_changed: true)
      _status, suggestion = propose

      suggestion.accept

      localization = @key.localizations.find_by(locale_id: @locale.id)
      assert_equal 'Organisationsträd', localization.reload.translated_value
      assert localization.is_changed
    end

    test 'accepting keeps array values intact' do
      _status, suggestion = propose(value: %w[sön mån tis])

      suggestion.accept

      assert_equal %w[sön mån tis],
                   @key.localizations.find_by(locale_id: @locale.id).translated_value
    end

    test 'proposing twice for the same key and locale updates in place' do
      status, first = propose(value: 'first')
      assert_equal :created, status

      status, second = propose(value: 'second')

      assert_equal :updated, status
      assert_equal first.id, second.id
      assert_equal 'second', second.reload.suggested_value
      assert_equal 1, Lit::AiSuggestion.count
    end

    test 'proposing does not overwrite a proposal a human has edited' do
      _status, suggestion = propose(value: 'machine')
      suggestion.update!(suggested_value: 'human', is_edited: true)

      status, kept = propose(value: 'machine again')

      assert_equal :kept_human_edit, status
      assert_equal 'human', kept.reload.suggested_value
    end

    test 'records the current value as base_value so later manual edits are detectable' do
      @key.localizations.create!(locale: @locale, translated_value: 'gammal', is_changed: true)
      Lit.init.cache.update_cache("sv.#{@key.localization_key}", 'gammal')

      _status, suggestion = propose

      assert_equal 'gammal', suggestion.base_value
      assert_not suggestion.stale?

      Lit.init.cache.update_cache("sv.#{@key.localization_key}", 'ändrad för hand')
      assert suggestion.stale?
    end

    test 'a proposal is destroyed together with its localization key' do
      _status, _suggestion = propose
      @key.destroy

      assert_equal 0, Lit::AiSuggestion.count
    end

    test 'pending scope excludes suggestions for deleted keys' do
      _status, _suggestion = propose
      @key.update!(is_deleted: true)

      assert_equal 0, Lit::AiSuggestion.pending.count
    end
  end
end

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

    # --- new translation or correction --------------------------------------

    def serve(locale, value)
      Lit.init.cache.update_cache("#{locale}.#{@key.localization_key}", value)
    end

    test 'a proposal for a key with no value yet is a new translation' do
      _status, suggestion = propose

      assert_not suggestion.is_correction
    end

    test 'a proposal for a key still showing the English text is a new translation' do
      serve('en', 'Organisation tree')
      serve('sv', 'Organisation tree')

      _status, suggestion = propose

      assert_not suggestion.is_correction
    end

    test 'a proposal for a key that is already translated is a correction' do
      serve('en', 'Organisation tree')
      serve('sv', 'Organisationsschema')

      _status, suggestion = propose

      assert suggestion.is_correction
    end

    test 'an English proposal for a key that already has English text is a correction' do
      en = Lit::Locale.where(locale: 'en').first_or_create!
      serve('en', 'Organisation tre')

      _status, suggestion = Lit::AiSuggestion.propose(localization_key: @key, locale: en,
                                                      value: 'Organisation tree')

      assert suggestion.is_correction
    end

    test 'an English proposal for a key with no English text is a new translation' do
      en = Lit::Locale.where(locale: 'en').first_or_create!

      _status, suggestion = Lit::AiSuggestion.propose(localization_key: @key, locale: en,
                                                      value: 'Organisation tree')

      assert_not suggestion.is_correction
    end

    test 'proposing the value already served stores nothing' do
      serve('sv', 'Organisationsträd')

      status, _suggestion = propose(value: ' Organisationsträd ')

      assert_equal :unchanged, status
      assert_equal 0, Lit::AiSuggestion.count
    end

    test 'proposing the value already served leaves an earlier proposal alone' do
      _status, earlier = propose(value: 'Organisationsschema')
      serve('sv', 'Organisationsträd')

      status, _suggestion = propose(value: 'Organisationsträd')

      assert_equal :unchanged, status
      assert_equal 'Organisationsschema', earlier.reload.suggested_value
    end

    test 'reclassify sorts existing proposals and drops the ones that change nothing' do
      _status, gap = propose(value: 'Organisationsträd')
      other = Lit::LocalizationKey.create!(localization_key: 'ai.suggestion.other')
      _status, same = Lit::AiSuggestion.propose(localization_key: other, locale: @locale, value: 'Samma')
      # translations a person made after the proposals were recorded
      serve('sv', 'Organisationsschema')
      Lit.init.cache.update_cache("sv.#{other.localization_key}", 'Samma')

      result = Lit::AiSuggestion.reclassify_all

      assert gap.reload.is_correction
      assert_not Lit::AiSuggestion.exists?(same.id)
      assert_equal({ new: 0, corrected: 1, removed_unchanged: 1 }, result)
    end

    test 'reclassify keeps a human-edited proposal even when it matches the current value' do
      _status, suggestion = propose(value: 'machine')
      suggestion.update!(suggested_value: 'Organisationsträd', is_edited: true)
      serve('sv', 'Organisationsträd')

      Lit::AiSuggestion.reclassify_all

      assert Lit::AiSuggestion.exists?(suggestion.id)
    end
  end
end

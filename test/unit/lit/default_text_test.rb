require 'test_helper'

module Lit
  # What a translator sees for a key whose text only exists in the code.
  class DefaultTextTest < ActiveSupport::TestCase
    # The placeholder Rails' `t` view helper passes as the default of its first
    # lookup (ActionView::Helpers::TranslationHelper::MISSING_TRANSLATION).
    RAILS_MISSING_MARKER = -(2**60)

    setup do
      Lit.init
      I18n.locale = :en
      @locale = Lit::Locale.where(locale: 'en').first_or_create!
      # tests share a thread, so one test's lookup would otherwise reach the next
      Thread.current[:lit_untranslated_key] = nil
    end

    def row(key)
      Lit::LocalizationKey.find_by(localization_key: key)&.localizations&.find_by(locale_id: @locale.id)
    end

    def existing_row(key, attributes = {})
      Lit::LocalizationKey.create!(localization_key: key)
                          .localizations.create!({ locale: @locale }.merge(attributes))
    end

    def view
      ActionView::Base.empty
    end

    test 'text passed to the t view helper reaches the translator' do
      view.t('default_text.view', default: 'Edit contract')

      assert_equal 'Edit contract', row('default_text.view').default_value
    end

    test 'text passed to I18n.t reaches the translator' do
      I18n.t('default_text.ruby', default: 'Edit contract')

      assert_equal 'Edit contract', row('default_text.ruby').default_value
    end

    test 'an empty row left behind by an earlier version is filled in' do
      empty = existing_row('default_text.old_row')

      view.t('default_text.old_row', default: 'Edit contract')

      assert_equal 'Edit contract', empty.reload.default_value
    end

    test 'an empty row somebody marked completed is left as it is' do
      completed = existing_row('default_text.completed', is_changed: true)

      view.t('default_text.completed', default: 'Edit contract')

      assert_nil completed.reload.default_value
    end

    test 'a row somebody translated keeps that translation' do
      translated = existing_row('default_text.human', translated_value: 'Rediger', is_changed: true)

      assert_equal 'Rediger', view.t('default_text.human', default: 'Edit contract')

      assert_equal 'Rediger', translated.reload.translation
      assert_nil translated.default_value
    end

    test 'text from the code never replaces a default already stored' do
      stored = existing_row('default_text.stored', default_value: 'Already here')

      Lit.init.cache.update_locale('en.default_text.stored', 'From the code')

      assert_equal 'Already here', stored.reload.default_value
    end

    test 'a default pointing at another key is not copied into the row' do
      target = existing_row('default_text.target', default_value: 'Target text')
      Lit.init.cache.update_cache(target.full_key, 'Target text')

      assert_equal 'Target text', I18n.t('default_text.pointer', default: :'default_text.target')

      assert_nil row('default_text.pointer').default_value
    end

    test 'a model attribute with no text stays empty instead of storing the marker' do
      assert_equal 'Some field', Lit::Locale.human_attribute_name(:some_field)

      assert_nil row('activerecord.attributes.lit/locale.some_field').default_value
    end

    test 'threads rendering at the same time keep their own keys' do
      I18n.backend.translate(:en, 'default_text.thread_a', { default: RAILS_MISSING_MARKER })
      Thread.new do
        I18n.backend.translate(:en, 'default_text.thread_b', { default: RAILS_MISSING_MARKER })
      end.join

      I18n.backend.translate(:en, nil, { default: ['Text for A'] })

      assert_equal 'Text for A', row('default_text.thread_a').default_value
      assert_nil row('default_text.thread_b').default_value
    end

    test 'a view default with no key stays away from the key rendered before it' do
      previous = existing_row('default_text.previous')
      view.t('default_text.previous')

      view.t(nil, default: 'Fallback text')

      assert_nil previous.reload.default_value
    end

    # --- code text met in another language ------------------------------------

    test 'text from a view rendered in another language also fills the English row' do
      I18n.with_locale(:pl) { view.t('default_text.pl_view', default: 'Edit contract') }

      assert_equal 'Edit contract', row('default_text.pl_view').default_value
    end

    test 'text from I18n.t in another language also fills the English row' do
      I18n.with_locale(:pl) { I18n.t('default_text.pl_ruby', default: 'Edit contract') }

      assert_equal 'Edit contract', row('default_text.pl_ruby').default_value
    end

    test 'an AI proposal for code text met in another language counts as new' do
      polish = Lit::Locale.where(locale: 'pl').first_or_create!
      I18n.with_locale(:pl) { view.t('default_text.pl_ai', default: 'Edit contract') }

      _status, suggestion = Lit::AiSuggestion.propose(
        localization_key: Lit::LocalizationKey.find_by!(localization_key: 'default_text.pl_ai'),
        locale: polish, value: 'Edytuj umowe'
      )

      assert_not suggestion.is_correction
    end

    test 'an English row with a translation keeps it when another language brings code text' do
      english = existing_row('default_text.pl_human', translated_value: 'Human text', is_changed: true)

      I18n.with_locale(:pl) { view.t('default_text.pl_human', default: 'Edit contract') }

      assert_equal 'Human text', english.reload.translation
      assert_nil english.default_value
    end

    test 'an English row with text keeps it when another language brings code text' do
      english = existing_row('default_text.pl_stored', default_value: 'Already here')

      I18n.with_locale(:pl) { view.t('default_text.pl_stored', default: 'Edit contract') }

      assert_equal 'Already here', english.reload.default_value
    end

    test 'a default pointing at another key does not reach the English row' do
      target = existing_row('default_text.pl_target', default_value: 'Target text')
      polish = Lit::Locale.where(locale: 'pl').first_or_create!
      Lit::LocalizationKey.find_by!(localization_key: 'default_text.pl_target')
                          .localizations.create!(locale: polish, default_value: 'Tekst')
      Lit.init.cache.update_cache('pl.default_text.pl_target', 'Tekst')
      Lit.init.cache.update_cache(target.full_key, 'Target text')

      I18n.with_locale(:pl) { I18n.t('default_text.pl_pointer', default: :'default_text.pl_target') }

      assert_nil row('default_text.pl_pointer')&.default_value
    end

    test 'text for a key Lit ignores is not stored' do
      original = Lit.ignored_keys
      Lit.ignored_keys = ['default_text_ignored']

      view.t('default_text_ignored.label', default: 'Edit contract')

      assert_nil Lit::LocalizationKey.find_by(localization_key: 'default_text_ignored.label')
    ensure
      Lit.ignored_keys = original
    end

    test 'a default with no key before it stores nothing' do
      assert_no_difference -> { Lit::Localization.count } do
        assert_equal 'On its own', I18n.t(nil, default: 'On its own')
      end
    end
  end
end

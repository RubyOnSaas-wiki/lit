require 'test_helper'

module Lit
  # A `default:` can be built while the page renders, for example from a
  # person's name, and nothing at this level tells it from a fixed text. Storing
  # it would serve one person's text to everybody after them.
  class DefaultTextTest < ActiveSupport::TestCase
    setup do
      Lit.init
      I18n.locale = :en
      @locale = Lit::Locale.where(locale: 'en').first_or_create!
    end

    def row(key)
      Lit::LocalizationKey.find_by(localization_key: key)&.localizations&.find_by(locale_id: @locale.id)
    end

    def view
      ActionView::Base.empty
    end

    test 'a default built in a view is not served to the next person' do
      assert_equal 'Welcome Anna', view.t('default_text.welcome', default: 'Welcome Anna')

      assert_equal 'Welcome Bob', view.t('default_text.welcome', default: 'Welcome Bob')
    end

    test 'a default built in Ruby is not served to the next caller' do
      assert_equal 'Upload of a.html failed', I18n.t('default_text.upload', default: 'Upload of a.html failed')

      assert_equal 'Upload of b.html failed', I18n.t('default_text.upload', default: 'Upload of b.html failed')
    end

    test 'a default stays out of the row' do
      view.t('default_text.row', default: 'Edit contract')

      assert_nil row('default_text.row').default_value
    end
  end
end

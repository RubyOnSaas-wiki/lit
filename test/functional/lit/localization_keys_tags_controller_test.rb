require 'test_helper'

module Lit
  # Tag filtering on the localization key lists.
  class LocalizationKeysTagsControllerTest < ActionController::TestCase
    tests Lit::LocalizationKeysController
    fixtures :all

    setup do
      Lit.authentication_function = nil
      I18n.locale = :en
      @routes = Lit::Engine.routes

      @billing = Lit::Tag.create!(name: 'billing')
      @hr = Lit::Tag.create!(name: 'hr-tree')
      @lonely = Lit::Tag.create!(name: 'lonely')

      @billing_key = lit_localization_keys(:hello_world)
      @hr_key = lit_localization_keys(:string)
      @untagged_key = lit_localization_keys(:array)

      @billing_key.tags << @billing
      @hr_key.tags << @hr
    end

    test 'filters keys down to the selected tag' do
      get :index, params: { tags: ['billing'] }

      assert_response :success
      keys = assigns(:localization_keys).to_a
      assert_includes keys, @billing_key
      assert_not_includes keys, @hr_key
      assert_not_includes keys, @untagged_key
    end

    test 'combines several tags with OR' do
      get :index, params: { tags: %w[billing hr-tree] }

      assert_response :success
      keys = assigns(:localization_keys).to_a
      assert_includes keys, @billing_key
      assert_includes keys, @hr_key
      assert_not_includes keys, @untagged_key
    end

    test 'ignores the blank placeholder a multiselect submits' do
      get :index, params: { tags: [''] }

      assert_response :success
      assert_includes assigns(:localization_keys).to_a, @untagged_key
    end

    test 'offers only tags that are active in the unfiltered scope' do
      get :index

      names = @controller.send(:tag_filter_options).map(&:name)
      assert_equal %w[billing hr-tree], names
    end

    test 'keeps offering every other tag while one is selected, so OR stays usable' do
      get :index, params: { tags: ['billing'] }

      names = @controller.send(:tag_filter_options).map(&:name)
      assert_includes names, 'billing'
      assert_includes names, 'hr-tree'
    end

    test 'still offers a selected tag that the key search excludes' do
      get :index, params: { tags: ['lonely'], key: 'scopes.hello_world' }

      names = @controller.send(:tag_filter_options).map(&:name)
      assert_includes names, 'lonely'
    end

    test 'builds the tag options without tripping postgres on SELECT DISTINCT + ORDER BY' do
      Lit::LocalizationKey.order_options.each do |order|
        get :index, params: { order: order, tags: ['billing'] }
        assert_response :success, "order #{order} failed"
        assert_nothing_raised { @controller.send(:tag_filter_options).to_a }
      end
    end

    test 'narrows the tag options to the not_translated tab' do
      @billing_key.update!(is_completed: true)

      get :not_translated

      names = @controller.send(:tag_filter_options).map(&:name)
      assert_not_includes names, 'billing'
      assert_includes names, 'hr-tree'
    end

    test 'the batch touch link carries the active tag filter' do
      get :index, params: { tags: ['billing'] }

      assert_match(/batch_touch[^"']*tags(%5B%5D|\[\])=billing/, response.body)
    end

    test 'renders the tag multiselect with only the active tags' do
      get :index

      assert_select 'select.js-tag-filter[multiple]' do
        assert_select 'option[value=?]', 'billing'
        assert_select 'option[value=?]', 'hr-tree'
        assert_select 'option[value=?]', 'lonely', count: 0
      end
    end

    test 'batch touch honours the tag filter' do
      Lit::LocalizationKey.update_all(updated_at: 2.days.ago)
      untouched_before = @untagged_key.reload.updated_at

      post :batch_touch, params: { tags: ['billing'] }, xhr: true

      assert_operator @billing_key.reload.updated_at, :>, 1.hour.ago
      assert_equal untouched_before.to_i, @untagged_key.reload.updated_at.to_i
    end
  end
end

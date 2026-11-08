require 'test_helper'

module Lit
  class LocalizationKeysControllerTest < ActionController::TestCase
    fixtures :all

    setup do
      Lit.authentication_function = nil
      I18n.locale = :en
      @routes = Lit::Engine.routes
      @localization_key = lit_localization_keys(:hello_world)
    end

    # GET /localization_keys/not_translated
    test 'should return only not completed localization keys' do
      @localization_key.update is_completed: true
      get :not_translated
      assert_response :success
      assert_not assigns(:localization_keys).include?(
        lit_localization_keys(:hello_world)
      )
    end

    # There where a bug - if someone tries to destroy localization key
    # `Lit.init.cache.delete_key` method is involved. This method was calling
    # `delete` on `@localization_keys` which could be nil and lead to
    # "NoMethodError: undefined method `delete' for nil:NilClass" error. This
    # test ensures lit/localization_keys#destroys works as expected when
    # Lit.loader.cache is a fresh object.

    # DELETE /localization_keys/:id
    test 'should set is_deleted flag of localization key when Lit.loader.cache is fresh object' do
      with_fresh_cache do
        delete :destroy, params: { id: @localization_key.id, format: :js }
        assert_response :success
        assert assigns(:localization_key).is_deleted
        assert Lit::LocalizationKey.active.find_by(id: @localization_key.id).blank?
        assert !Lit.init.cache.has_key?("#{I18n.locale}.#{@localization_key.localization_key}")
      end
    end

    # GET /localization_keys
    test 'should find string value' do
      get :index, params: { key: 'value' }
      assert_response :success
      assert assigns(:localization_keys).include?(lit_localization_keys(:string))
      assert_not assigns(:localization_keys).include?(lit_localization_keys(:array))
    end

    # GET /localization_keys
    test 'should find array value' do
      get :index, params: { key: 'two' }
      assert_response :success
      assert_not assigns(:localization_keys).include?(lit_localization_keys(:string))
      assert assigns(:localization_keys).include?(lit_localization_keys(:array))
    end

    # PUT /localization_keys/:id/change_completed
    test 'should change localization key to completed' do
      assert_not @localization_key.is_completed
      put :change_completed, params: { id: @localization_key.id }, format: :js
      assert_response :success
      assert @localization_key.reload.is_completed
    end

    # PUT /localization_keys/:id/restore_deleted
    test 'should restore localization key' do
      @localization_key.update is_deleted: true
      put :restore_deleted, params: { id: @localization_key.id }, format: :js
      assert_response :success
      assert_not @localization_key.reload.is_deleted
    end

    test 'touches search results in batch' do
      v = lit_localization_keys(:string)
      a = lit_localization_keys(:array)
      v.update_column :updated_at, 1.day.ago
      a.update_column :updated_at, 1.day.ago
      post :batch_touch, params: { key: 'value' }, format: :js
      assert_in_delta(v.reload.updated_at, 1.second.ago, 5)
      assert_in_delta(a.reload.updated_at, 1.day.ago, 5)
    end

    test 'wont fail when there wont be any search results when touching in batch' do
      post :batch_touch, params: { key: 'valuefoobar' }, format: :js
      assert_response :success
    end

    test 'the key-level icon shows whether the key is completed, not starred' do
      @localization_key.update_columns(is_completed: true, is_starred: false)

      get :index

      assert_select "tr.localization_key_row[data-id='#{@localization_key.id}'] a.check_icon i.fa-check-circle"
    end

    test 'the list shows a translation the cache does not hold yet' do
      row = text_row('only.in.database', translated_value: 'From the database', is_changed: true)

      get :index, params: { key: 'only.in.database' }

      assert_select "td.localization_row[data-id='#{row.id}']", /From the database/
    end

    %w[
      activerecord.errors.models.company.attributes.logo.invalid
      activemodel.errors.models.search.attributes.term.blank
      errors.attributes.cv.too_large
      activerecord.attributes.company.cvr_number
      activemodel.attributes.search.term
      attributes.hiring_advice
      activerecord.models.company
      activerecord.state_machines.user.state.states.active
      helpers.label.company.name
    ].each do |name|
      test "#{name} is left out of the list while it is empty" do
        probe = text_row(name).localization_key

        get :index

        assert_not_includes assigns(:localization_keys).to_a, probe
      end
    end

    test 'a Rails lookup key with text stays in the list' do
      filled = text_row('activerecord.attributes.company.name', default_value: 'Company name').localization_key

      get :index

      assert_includes assigns(:localization_keys).to_a, filled
    end

    %w[errors.messages.not_in_future flash.billing.destroy.notice billing.invoice.title].each do |name|
      test "#{name} stays in the list even while it is empty" do
        real = text_row(name).localization_key

        get :index

        assert_includes assigns(:localization_keys).to_a, real
      end
    end

    test 'a row without a key does not stop empty Rails lookup keys being hidden' do
      Lit::Localization.new(locale: Lit::Locale.where(locale: 'en').first_or_create!, default_value: 'orphan')
                       .save!(validate: false)
      probe = text_row('helpers.label.company.name').localization_key

      get :index

      assert_not_includes assigns(:localization_keys).to_a, probe
    end

    test 'the sidebar link brings the empty Rails lookup keys back' do
      probe = text_row('helpers.label.company.name').localization_key

      get :index
      assert_select "a[href*='show_empty_lookups=1']"

      get :index, params: { show_empty_lookups: 1 }
      assert_includes assigns(:localization_keys).to_a, probe
    end

    test 'searching for an empty Rails lookup key finds it' do
      probe = text_row('activerecord.errors.models.company.carrierwave_download_error').localization_key

      get :index, params: { key: 'carrierwave_download_error' }

      assert_includes assigns(:localization_keys).to_a, probe
    end

    private

    def text_row(name, attributes = {})
      Lit::LocalizationKey.create!(localization_key: name).localizations.create!(
        { locale: Lit::Locale.where(locale: 'en').first_or_create! }.merge(attributes)
      )
    end

    def with_fresh_cache
      old_cache, old_backend = Lit.loader.cache, I18n.backend
      Lit.loader.cache       = Lit::Cache.new
      I18n.backend           = Lit::I18nBackend.new(Lit.loader.cache)

      yield
    ensure
      Lit.loader.cache, I18n.backend = old_cache, old_backend
    end
  end
end

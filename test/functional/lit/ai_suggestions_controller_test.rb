require 'test_helper'

module Lit
  class AiSuggestionsControllerTest < ActionController::TestCase
    include ActiveJob::TestHelper

    setup do
      Lit.authentication_function = nil
      Lit.ai_api_enabled = true
      Lit.ai_api_key = 'ai-key'
      Lit::Engine.routes.clear!
      Dummy::Application.reload_routes!
      @routes = Lit::Engine.routes

      Lit::AiSuggestion.delete_all
      Lit::LocalizationKeyTag.delete_all
      Lit::Tag.delete_all
      Lit::Localization.delete_all
      Lit::LocalizationKey.delete_all
      Lit.init

      @sv = Lit::Locale.where(locale: 'sv').first_or_create!
      @da = Lit::Locale.where(locale: 'da').first_or_create!
      @hr_key = Lit::LocalizationKey.create!(localization_key: 'hr.tree.title')
      @billing_key = Lit::LocalizationKey.create!(localization_key: 'billing.invoice')
      @hr_key.tags << Lit::Tag.create!(name: 'hr-tree')
      @billing_key.tags << Lit::Tag.create!(name: 'billing')

      _s, @hr_suggestion = Lit::AiSuggestion.propose(
        localization_key: @hr_key, locale: @sv, value: 'Organisationsträd'
      )
      _s, @billing_suggestion = Lit::AiSuggestion.propose(
        localization_key: @billing_key, locale: @da, value: 'Faktura'
      )
    end

    teardown do
      Lit.ai_api_enabled = nil
      Lit.ai_api_key = nil
    end

    test 'lists pending suggestions' do
      get :index

      assert_response :success
      assert_equal 2, assigns(:ai_suggestions).size
    end

    test 'hides suggestions for deleted keys' do
      @hr_key.update!(is_deleted: true)

      get :index

      assert_not_includes assigns(:ai_suggestions).to_a, @hr_suggestion
    end

    test 'filters the tab by tag' do
      get :index, params: { tags: ['billing'] }

      assert_equal [@billing_suggestion], assigns(:ai_suggestions).to_a
    end

    test 'filters the tab by locale' do
      get :index, params: { locale: 'sv' }

      assert_equal [@hr_suggestion], assigns(:ai_suggestions).to_a
    end

    test 'offers only tags active on this tab' do
      get :index

      assert_equal %w[billing hr-tree], @controller.send(:tag_filter_options).map(&:name)
    end

    test 'the javascript responses target selectors the view actually renders' do
      get :index
      body = response.body
      # class tokens, not whole attributes: these sit alongside bootstrap classes
      assert_match(/class="[^"]*\bai-row\b/, body)
      assert_match(/class="[^"]*\bai-group\b/, body)
      assert_match(/class="[^"]*\bai-value\b/, body)
      assert_match(/js-edit-suggestion/, body)

      post :accept, params: { id: @hr_suggestion.id }, xhr: true
      assert_match(/\.ai-row\[data-id=/, response.body)
      assert_match(/\.ai-group/, response.body)
    end

    test 'editing re-renders the row with the same selectors' do
      patch :update, params: { id: @hr_suggestion.id,
                               ai_suggestion: { suggested_value: 'Ny' } }, xhr: true

      assert_match(/\.ai-row\[data-id=/, response.body)
      assert_match(/class=\\"ai-row\\"/, response.body)
    end

    test 'accepting one writes the translation and removes the proposal' do
      post :accept, params: { id: @hr_suggestion.id }, xhr: true

      localization = @hr_key.localizations.find_by(locale_id: @sv.id)
      assert_equal 'Organisationsträd', localization.translated_value
      assert localization.is_changed
      assert_not Lit::AiSuggestion.exists?(@hr_suggestion.id)
    end

    test 'rejecting removes the proposal and changes no translation' do
      delete :destroy, params: { id: @hr_suggestion.id }, xhr: true

      assert_not Lit::AiSuggestion.exists?(@hr_suggestion.id)
      assert_nil @hr_key.localizations.find_by(locale_id: @sv.id)
    end

    test 'editing stores the new value and flags it as human edited' do
      patch :update, params: { id: @hr_suggestion.id,
                               ai_suggestion: { suggested_value: 'Handredigerad' } }, xhr: true

      @hr_suggestion.reload
      assert_equal 'Handredigerad', @hr_suggestion.suggested_value
      assert @hr_suggestion.is_edited
    end

    test 'accept all enqueues a background job scoped to the current filter' do
      assert_enqueued_with(job: Lit::AcceptAiSuggestionsJob,
                           args: [{ 'tags' => ['billing'] }]) do
        post :accept_all, params: { tags: ['billing'] }
      end
      assert_redirected_to ai_suggestions_path(tags: ['billing'])
    end

    test 'accept all does not accept anything inline' do
      post :accept_all, params: {}

      assert_equal 2, Lit::AiSuggestion.count
    end

    test 'reject all destroys only the filtered proposals' do
      delete :reject_all, params: { tags: ['billing'] }

      assert Lit::AiSuggestion.exists?(@hr_suggestion.id)
      assert_not Lit::AiSuggestion.exists?(@billing_suggestion.id)
    end

    test 'the accept-all job accepts every suggestion in the filter' do
      perform_enqueued_jobs do
        Lit::AcceptAiSuggestionsJob.perform_later('tags' => ['billing'])
      end

      assert_not Lit::AiSuggestion.exists?(@billing_suggestion.id)
      assert Lit::AiSuggestion.exists?(@hr_suggestion.id)
      assert_equal 'Faktura',
                   @billing_key.localizations.find_by(locale_id: @da.id).translated_value
    end

    test 'inherits host authentication from Lit::ApplicationController' do
      assert_operator Lit::AiSuggestionsController, :<, Lit::ApplicationController
    end
  end
end

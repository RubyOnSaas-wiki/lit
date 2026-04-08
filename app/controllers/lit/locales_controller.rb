require_dependency 'lit/application_controller'

module Lit
  class LocalesController < ApplicationController
    def index
      @locales = Locale.ordered

      respond_to do |format|
        format.html # index.html.erb
        format.json { render json: @locales }
      end
    end

    def new
    end

    def create
      locale_code = params[:locale_code]&.strip&.downcase

      validation_error = validate_locale_creation(locale_code)
      return redirect_to lit.new_locale_path, alert: validation_error if validation_error

      ::Lit::CreateLocaleWithTranslationsJob.perform_later(locale_code)
      redirect_to lit.new_locale_path, notice: "Language '#{locale_code}' creation has been queued. Translations will be processed in the background."
    end

    def hide
      @locale = Locale.find(params[:id])
      @locale.toggle :is_hidden
      @locale.save
      respond_to :js
    end

    def destroy
      @locale = Locale.find(params[:id])
      @locale.destroy

      respond_to do |format|
        format.html { redirect_to locales_url }
        format.json { head :no_content }
      end
    end

    private

    def validate_locale_creation(locale_code)
      return "Language code cannot be blank" if locale_code.blank?
      return "Language '#{locale_code}' already exists" if ::Lit::Locale.exists?(locale: locale_code)
      return 'Google Translation is not configured. Please configure it in your Lit initializer.' unless ::Lit::CloudTranslation.provider

      nil
    end
  end
end

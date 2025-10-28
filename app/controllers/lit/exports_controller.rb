require_dependency 'lit/application_controller'

module Lit
  class ExportsController < ::Lit::ApplicationController
    def index
      @locales = Lit::Locale.ordered.visible
    end

    def export
      locale = Lit::Locale.find_by!(locale: params[:locale])
      
      begin
        export_service = Lit::ExportService.new(locale)
        yaml_content = export_service.generate_yaml
        
        filename = "#{locale.locale}.yml"
        
        send_data yaml_content, 
                  filename: filename,
                  type: 'application/x-yaml',
                  disposition: 'attachment'
      rescue => e
        redirect_to lit.exports_path, alert: "Export failed: #{e.message}"
      end
    end
  end
end

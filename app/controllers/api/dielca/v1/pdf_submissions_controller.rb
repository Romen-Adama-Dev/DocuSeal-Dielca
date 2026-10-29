# frozen_string_literal: true

module Api
  module Dielca
    module V1
      class PdfSubmissionsController < ApiBaseController
        before_action :require_connector!

        def capabilities
          load_layout!
          render json: { version: 1, mode: 'bc_pdf', idempotent: true,
                         authorized_signer_selection: true, customer_summary: true, free_signing: true,
                         personal_identity_validation: true, copy_email_confirmation: true, report_layouts: true,
                         layout_template_id: @layout.id, max_bytes: ::Dielca::PdfSubmission::MAX_BYTES,
                         max_pages: ::Dielca::PdfSubmission::MAX_PAGES }
        end

        def create
          load_layout!
          authorize!(:create, Submission.new(account: current_account))
          record = ::Dielca::PdfSubmission.call(user: current_user, layout: @layout, params:)
          authorize!(:read, record.submission)
          render json: { request_id: record.request_id, submission_id: record.submission_id,
                         submitter_id: record.submitter_id, pdf_sha256: record.pdf_sha256,
                         sign_url: submit_form_url(record.submitter.slug, **Docuseal.default_url_options),
                         status: 'ready' }, status: :created
        end

        def selection
          record = ::Dielca::PdfImport.find_by!(account: current_account, request_id: params[:request_id])
          authorize!(:read, record.submission)
          render json: { request_id: record.request_id, selected_signer_id: record.selected_signer_id,
                         signer_name: record.submitter.values[record.name_field_uuid],
                         signer_id_document_no: record.submitter.values[record.id_field_uuid],
                         copy_email: record.submitter.metadata['dielca_copy_email'] }
        end

        # Rails checks handlers in reverse order: register the broad fallback first.
        rescue_from StandardError do
          # Never log exception text, parameters, signed links or credentials.
          Rails.logger.error('DIELCA_IMPORT_FAILED')
          render json: { error: { code: 'IMPORT_FAILED' } }, status: :service_unavailable
        end

        rescue_from ::Dielca::PdfSubmission::Error do |error|
          details = { code: error.code }
          if error.code == 'REPORT_LAYOUT_NOT_CONFIGURED'
            details[:message] = ::Dielca::ReportLayout::NOT_CONFIGURED_MESSAGE
            details[:portal_url] = dielca_import_error_url(**Docuseal.default_url_options)
          end
          render json: { error: details }, status: error.status
        end

        rescue_from CanCan::AccessDenied do
          render json: { error: { code: 'IMPORT_FORBIDDEN' } }, status: :forbidden
        end

        private

        def current_user
          @connector_user ||= if request.headers['X-Auth-Token'].present?
                                hash = Digest::SHA256.hexdigest(request.headers['X-Auth-Token'])
                                User.joins(:access_token).active.find_by(access_token: { sha256: hash })
                              end
        end

        def require_connector!
          configured_user = ENV['DIELCA_BC_USER_ID'].to_s
          if configured_user.blank? || ENV['DIELCA_BC_LAYOUT_TEMPLATE_ID'].blank?
            raise ::Dielca::PdfSubmission::Error.new('IMPORT_DISABLED', :service_unavailable)
          end
          unless request.headers['X-Auth-Token'].present? && configured_user == current_user.id.to_s
            raise CanCan::AccessDenied
          end
          required_columns = %w[authorized_signers customer_data selected_signer_id id_field_uuid signer_mode]
          unless ::Dielca::PdfImport.table_exists? &&
                 (required_columns - ::Dielca::PdfImport.column_names).empty?
            raise ::Dielca::PdfSubmission::Error.new('IMPORT_MIGRATION_REQUIRED', :service_unavailable)
          end
        end

        def load_layout!
          id = ENV.fetch('DIELCA_BC_LAYOUT_TEMPLATE_ID')
          requested = params[:layout_template_id].to_s
          raise ::Dielca::PdfSubmission::Error.new('LAYOUT_NOT_ALLOWED', :forbidden) unless requested == id

          @layout = Template.find_by(id:, account_id: current_account.id, archived_at: nil)
          raise ::Dielca::PdfSubmission::Error.new('LAYOUT_INVALID') unless @layout

          authorize!(:read, @layout)
          ::Dielca::PdfLayout.fields(@layout, document_uuid: 'validation', page: 0, role_uuid: 'validation')
        end
      end
    end
  end
end

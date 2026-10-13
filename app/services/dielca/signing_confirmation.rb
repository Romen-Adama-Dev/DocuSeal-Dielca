# frozen_string_literal: true

module Dielca
  module SigningConfirmation
    module_function

    def ready?(record, submitter)
      AuthorizedSignerSelection.validate_identity!(record, submitter)
      CopyEmail.validate!(record, submitter)
      true
    rescue Submitters::SubmitValues::ValidationError
      false
    end

    def confirm!(submitter, params)
      submitter.with_lock do
        record = PdfImport.find_by!(submitter_id: submitter.id, submission_id: submitter.submission_id)
        AuthorizedSignerSelection.validate_open!(submitter)
        if record.free_signing?
          name = params[:signer_name].to_s.strip
          document = AuthorizedSignerSelection.validated_document!(params[:personal_id])
          if submitter.values[record.name_field_uuid] != name || submitter.values[record.id_field_uuid] != document
            submitter.values = {}
          end
          submitter.values[record.name_field_uuid] = name
          submitter.values[record.id_field_uuid] = document
        end
        AuthorizedSignerSelection.validate_identity!(record, submitter)
        CopyEmail.confirm!(record, submitter, params)
        submitter.save!
      end
    end
  end
end

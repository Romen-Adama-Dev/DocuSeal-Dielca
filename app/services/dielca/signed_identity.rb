# frozen_string_literal: true

module Dielca
  module SignedIdentity
    def assign_completed_attributes(submitter, request, validate_required: true)
      # Only submissions registered by our importer may synchronize identity.
      # Run before upstream stamp/default generation and completion processing.
      if !submitter.completed_at? && PdfImport.table_exists?
        record = PdfImport.find_by(submission_id: submitter.submission_id, submitter_id: submitter.id)
        if record
          value = submitter.values[record.name_field_uuid]
          unless value.is_a?(String) && value.strip.present? && value.length <= 200
            raise Submitters::SubmitValues::ValidationError, 'Nombre obligatorio'
          end
          submitter.name = value.strip
        end
      end
      super
    end
  end
end

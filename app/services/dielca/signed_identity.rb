# frozen_string_literal: true

module Dielca
  module SignedIdentity
    SIGNATURE_TYPES = %w[signature initials].freeze

    def update_submitter!(submitter, params, request, validate_required: true)
      if PdfImport.table_exists? && PdfImport.exists?(submitter_id: submitter.id,
                                                      submission_id: submitter.submission_id)
        submitter.with_lock do
          AuthorizedSignerSelection.validate_open!(submitter)
          record = PdfImport.find_by!(submitter_id: submitter.id, submission_id: submitter.submission_id)
          signature_ids = (submitter.submission.template_fields || submitter.template.fields)
                          .select { |field| SIGNATURE_TYPES.include?(field['type']) }.pluck('uuid')
          values = params[:values]
          if values.respond_to?(:keys) && signature_ids.any? { |uuid| values[uuid].present? }
            AuthorizedSignerSelection.validate_identity!(record, submitter)
            CopyEmail.validate!(record, submitter)
            validate_incoming_identity!(record, submitter, values)
          end
          super
        end
      else
        super
      end
    end

    def validate_incoming_identity!(record, submitter, values)
      candidate = submitter.dup
      candidate.values = submitter.values.deep_dup
      [record.name_field_uuid, record.id_field_uuid].each do |uuid|
        candidate.values[uuid] = values[uuid] if values.key?(uuid)
      end
      AuthorizedSignerSelection.validate_identity!(record, candidate)
    end

    def assign_completed_attributes(submitter, request, validate_required: true)
      # Only submissions registered by our importer may synchronize identity.
      # Run before upstream stamp/default generation and completion processing.
      if !submitter.completed_at? && PdfImport.table_exists?
        record = PdfImport.find_by(submission_id: submitter.submission_id, submitter_id: submitter.id)
        if record
          AuthorizedSignerSelection.validate_identity!(record, submitter)
          CopyEmail.validate!(record, submitter)
          value = submitter.values[record.name_field_uuid]
          unless value.is_a?(String) && value.strip.present? && value.length <= 200
            raise Submitters::SubmitValues::ValidationError, 'Nombre obligatorio'
          end

          submitter.name = value.strip
          SingleLineIdentity.fit!(submitter)
        end
      end
      super
    end
  end
end

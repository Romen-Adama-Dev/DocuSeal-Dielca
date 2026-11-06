# frozen_string_literal: true

module Dielca
  module AuthorizedSignerSelection
    module_function

    def select!(submitter, person_id)
      submitter.with_lock do
        record = PdfImport.find_by!(submission_id: submitter.submission_id, submitter_id: submitter.id)
        if record.signer_mode == 'free'
          raise Submitters::SubmitValues::ValidationError, 'Esta firma requiere datos escritos.'
        end

        validate_open!(submitter)
        if record.signer_mode == 'selectable' && person_id == 'other'
          select_other!(record, submitter)
          next
        end

        person = record.authorized_signers.find { |s| s['id'] == person_id }
        raise Submitters::SubmitValues::ValidationError, 'Selecciona un autorizado de este cliente.' unless person

        document = validated_document!(person['id_document_no'])

        # A change of person must require a new signature, never retain a previous drawing.
        submitter.values = {} if record.selected_signer_id != person['id']
        submitter.name = person['name']
        submitter.values[record.name_field_uuid] = person['name']
        submitter.values[record.id_field_uuid] = document
        submitter.metadata = submitter.metadata.merge('authorized_person_id' => person['id'],
                                                      'signer_selection' => 'authorized',
                                                      'signer_contact_number' => person['contact_number'],
                                                      'signer_job_title' => person['job_title'])
        submitter.metadata = submitter.metadata.except('dielca_copy_email') if record.selected_signer_id != person['id']
        submitter.save!
        record.update!(selected_signer_id: person['id'])
      end
    end

    def select_other!(record, submitter)
      if record.selected_signer_id != 'other'
        submitter.values = {}
        submitter.name = 'Firmante por identificar'
        submitter.metadata = submitter.metadata.except('authorized_person_id', 'signer_contact_number',
                                                       'signer_job_title', 'dielca_copy_email')
      end
      submitter.metadata = submitter.metadata.merge('signer_selection' => 'other')
      submitter.save!
      record.update!(selected_signer_id: 'other')
    end

    def validate_open!(submitter)
      submission = submitter.submission
      if submitter.completed_at? || submitter.declined_at? || submission.completed_at? ||
         submission.archived_at? || submission.template&.archived_at? || submission.expired? ||
         submitter.account.archived_at?
        raise Submitters::SubmitValues::ValidationError, 'La firma no admite cambios de autorizado.'
      end
    end

    def validate_identity!(record, submitter)
      if record.free_signing?
        [[record.name_field_uuid, 100, 'Nombre obligatorio'],
         [record.id_field_uuid, 30, 'DNI/NIF obligatorio']].each do |uuid, max_length, message|
          value = submitter.values[uuid]
          unless value.is_a?(String) && value.strip.present? && value.length <= max_length &&
                 value.exclude?("\0") && !value.match?(/[\r\n]/)
            raise Submitters::SubmitValues::ValidationError, message
          end
        end
        submitter.values[record.id_field_uuid] = validated_document!(submitter.values[record.id_field_uuid])
        return
      end
      person = record.authorized_signers.find { |s| s['id'] == record.selected_signer_id }
      document = SpanishIdentity.normalize(submitter.values[record.id_field_uuid])
      unless person && submitter.values[record.name_field_uuid] == person['name'] &&
             document == SpanishIdentity.normalize(person['id_document_no'])
        raise Submitters::SubmitValues::ValidationError, 'Selecciona un autorizado antes de firmar.'
      end

      submitter.values[record.id_field_uuid] = validated_document!(person['id_document_no'])

      person
    end

    def validated_document!(value)
      document = SpanishIdentity.normalize(value)
      error = SpanishIdentity.error(document)
      raise Submitters::SubmitValues::ValidationError, error if error

      document
    end
  end
end

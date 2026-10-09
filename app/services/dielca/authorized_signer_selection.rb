# frozen_string_literal: true

module Dielca
  module AuthorizedSignerSelection
    module_function

    def select!(submitter, person_id)
      submitter.with_lock do
        record = PdfImport.find_by!(submission_id: submitter.submission_id, submitter_id: submitter.id)
        validate_open!(submitter)
        person = record.authorized_signers.find { |s| s['id'] == person_id }
        raise Submitters::SubmitValues::ValidationError, 'Selecciona un autorizado de este cliente.' unless person

        # A change of person must require a new signature, never retain a previous drawing.
        submitter.values = {} if record.selected_signer_id != person['id']
        submitter.name = person['name']
        submitter.values[record.name_field_uuid] = person['name']
        submitter.values[record.id_field_uuid] = person['id_document_no']
        submitter.metadata = submitter.metadata.merge('authorized_person_id' => person['id'],
                                                      'signer_contact_number' => person['contact_number'],
                                                      'signer_job_title' => person['job_title'])
        submitter.save!
        record.update!(selected_signer_id: person['id'])
      end
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
      person = record.authorized_signers.find { |s| s['id'] == record.selected_signer_id }
      unless person && submitter.values[record.name_field_uuid] == person['name'] &&
             submitter.values[record.id_field_uuid] == person['id_document_no']
        raise Submitters::SubmitValues::ValidationError, 'Selecciona un autorizado antes de firmar.'
      end
      person
    end
  end
end

# frozen_string_literal: true

module DielcaHelper
  def dielca_signing_fields(submitter)
    fields = Submissions.filtered_conditions_fields(submitter)
    return fields unless Dielca::PdfImport.table_exists?

    record = Dielca::PdfImport.find_by(submitter_id: submitter.id, submission_id: submitter.submission_id)
    return fields unless record&.free_signing?

    fields.map do |field|
      next field unless field['uuid'] == record.id_field_uuid

      field.deep_dup.merge('title' => 'DNI/NIE',
                           'preferences' => (field['preferences'] || {}).merge('dielca_personal_identity' => true))
    end
  end
end

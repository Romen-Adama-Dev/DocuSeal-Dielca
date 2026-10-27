# frozen_string_literal: true

RSpec.describe Dielca::SignedIdentity do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:, only_field_types: ['text']) }
  let(:submission) { create(:submission, :with_submitters, template:) }
  let(:submitter) { submission.submitters.first }
  let(:id_uuid) { SecureRandom.uuid }
  let(:person_id) { SecureRandom.uuid }
  let(:field_uuid) { template.fields.first['uuid'] }
  let(:request) { double(remote_ip: '127.0.0.1', user_agent: 'test', params: {}) }

  def register_import
    Dielca::PdfImport.create!(account: submission.account, request_id: SecureRandom.uuid,
                             pdf_sha256: '0' * 64, fingerprint: '0' * 64,
                             submission:, submitter:, name_field_uuid: field_uuid, id_field_uuid: id_uuid,
                             selected_signer_id: person_id, customer_data: { 'copy_email_required' => false },
                             authorized_signers: [{ 'id' => person_id, 'name' => 'Nombre escrito',
                                                    'id_document_no' => '12345678Z' }])
    submitter.metadata = { 'dielca_copy_email' => { 'confirmed' => true, 'skipped' => true, 'recipients' => [] } }
  end

  it 'synchronizes the written name before completion defaults and audit processing' do
    register_import
    submitter.values = { field_uuid => 'Nombre escrito', id_uuid => '12345678Z' }
    Submitters::SubmitValues.assign_completed_attributes(submitter, request, validate_required: false)
    expect(submitter.name).to eq('Nombre escrito')
    expect(submitter.completed_at).to be_present
  end

  it 'does not change identity for an upstream submission' do
    original = submitter.name
    submitter.values = { field_uuid => 'Nombre escrito', id_uuid => '12345678Z' }
    Submitters::SubmitValues.assign_completed_attributes(submitter, request, validate_required: false)
    expect(submitter.name).to eq(original)
  end

  it 'rejects empty identity for imports before completing' do
    register_import
    submitter.values = { field_uuid => ' ' }
    expect do
      Submitters::SubmitValues.assign_completed_attributes(submitter, request, validate_required: false)
    end.to raise_error(Submitters::SubmitValues::ValidationError, 'Selecciona un autorizado antes de firmar.')
    expect(submitter.completed_at).to be_nil
  end

  [
    ['2026-10-27 09:26:00 UTC', "27/10/2026\n09:26:00"],
    ['2026-07-15 09:26:00 UTC', "15/07/2026\n10:26:00"]
  ].each do |instant, expected|
    it "stamps the server completion time in Canary time at #{instant}" do
      register_import
      field = template.fields.first.deep_dup.merge('uuid' => 'timestamp', 'name' => 'Fecha y hora de firma',
                                                  'required' => false, 'readonly' => true,
                                                  'preferences' => { 'dielca_signing_timestamp' => true })
      template.update!(fields: template.fields + [field])
      submission.update!(template_fields: template.fields)
      submitter.values = { field_uuid => 'Nombre escrito', id_uuid => '12345678Z', 'timestamp' => 'forged client date' }
      travel_to Time.parse(instant) do
        Submitters::SubmitValues.assign_completed_attributes(submitter, request, validate_required: false)
        expect(submitter.completed_at).to eq(Time.current)
        expect(submitter.values['timestamp']).to eq(expected)
      end
      # Rendering or mail generation at a later date does not change the stamped value.
      travel_to Time.parse(instant) + 3.days do
        Dielca::SigningTimestamp.assign!(submitter)
        expect(submitter.values['timestamp']).to eq(expected)
      end
    end
  end

  it 'does not stamp before completion or add timestamp fields to older layouts' do
    field = template.fields.first.deep_dup.merge('uuid' => 'timestamp',
                                               'preferences' => { 'dielca_signing_timestamp' => true })
    template.update!(fields: [field])
    Dielca::SigningTimestamp.assign!(submitter)
    expect(submitter.values).not_to have_key('timestamp')
    template.update!(fields: [])
    submission.update!(template_fields: [])
    submitter.completed_at = Time.current
    Dielca::SigningTimestamp.assign!(submitter)
    expect(submitter.values).not_to have_key('timestamp')
  end

end

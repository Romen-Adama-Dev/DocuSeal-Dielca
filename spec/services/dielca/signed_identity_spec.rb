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
end

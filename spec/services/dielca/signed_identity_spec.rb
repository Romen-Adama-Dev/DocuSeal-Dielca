# frozen_string_literal: true

RSpec.describe Dielca::SignedIdentity do
  let(:template) { create(:template, only_field_types: ['text']) }
  let(:submission) { create(:submission, :with_submitters, template:) }
  let(:submitter) { submission.submitters.first }
  let(:field_uuid) { template.fields.first['uuid'] }
  let(:request) { double(remote_ip: '127.0.0.1', user_agent: 'test', params: {}) }

  def register_import
    Dielca::PdfImport.create!(account: submission.account, request_id: SecureRandom.uuid,
                             pdf_sha256: '0' * 64, fingerprint: '0' * 64,
                             submission:, submitter:, name_field_uuid: field_uuid)
  end

  it 'synchronizes the written name before completion defaults and audit processing' do
    register_import
    submitter.values = { field_uuid => 'Nombre escrito' }
    Submitters::SubmitValues.assign_completed_attributes(submitter, request, validate_required: false)
    expect(submitter.name).to eq('Nombre escrito')
    expect(submitter.completed_at).to be_present
  end

  it 'does not change identity for an upstream submission' do
    original = submitter.name
    submitter.values = { field_uuid => 'Nombre escrito' }
    Submitters::SubmitValues.assign_completed_attributes(submitter, request, validate_required: false)
    expect(submitter.name).to eq(original)
  end

  it 'rejects empty identity for imports before completing' do
    register_import
    submitter.values = { field_uuid => ' ' }
    expect do
      Submitters::SubmitValues.assign_completed_attributes(submitter, request, validate_required: false)
    end.to raise_error(Submitters::SubmitValues::ValidationError, 'Nombre obligatorio')
    expect(submitter.completed_at).to be_nil
  end
end

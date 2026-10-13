# frozen_string_literal: true

RSpec.describe Dielca::SignedCopyMailer do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:) }
  let(:submission) { create(:submission, :with_submitters, template:) }
  let(:submitter) { submission.submitters.first }
  let(:bytes) { Rails.root.join('spec/fixtures/sample-document.pdf').binread }

  it 'attaches separate signed PDF and audit and hides extra recipients in BCC' do
    submitter.update!(metadata: {
                        'document_type' => 'PostedShipment', 'document_number' => 'ALB-DEMO',
                        'dielca_copy_email' => { 'primary' => 'persona@example.invalid',
                                                 'additional' => ['extra@example.invalid', 'persona@example.invalid'] }
                      })
    submitter.documents.attach(io: StringIO.new(bytes), filename: 'signed-demo.pdf', content_type: 'application/pdf')
    submission.audit_trail.attach(io: StringIO.new(bytes), filename: 'audit-demo.pdf', content_type: 'application/pdf')
    message = described_class.signed_copy(submitter).message
    expect(message.subject).to eq('Documento firmado: Albarán ALB-DEMO')
    expect(message.to).to eq(['persona@example.invalid'])
    expect(message.bcc).to eq(['extra@example.invalid'])
    expect(message.attachments.map(&:filename)).to eq(['documento-firmado-1.pdf', 'auditoria.pdf'])
    expect(message.attachments.map { |item| item.body.decoded }).to eq([bytes, bytes])
  end
end

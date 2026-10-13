# frozen_string_literal: true

RSpec.describe Dielca::SendSignedCopyJob do
  let(:account) { create(:account) }
  let(:author) { create(:user, account:) }
  let(:template) { create(:template, account:, author:) }
  let(:submission) { create(:submission, :with_submitters, template:, completed_at: Time.current) }
  let(:submitter) { submission.submitters.first }

  before do
    submitter.update!(completed_at: Time.current, metadata: {
                        'dielca_copy_email' => { 'confirmed' => true, 'skipped' => false, 'status' => 'pending',
                                                 'primary' => 'persona@example.invalid',
                                                 'recipients' => ['persona@example.invalid'] }
                      })
    Dielca::PdfImport.create!(account: submission.account, request_id: SecureRandom.uuid,
                              pdf_sha256: '0' * 64, fingerprint: '0' * 64, submission:, submitter:,
                              name_field_uuid: 'name', id_field_uuid: 'id', signer_mode: 'free')
    allow(Submissions::EnsureResultGenerated).to receive(:call)
    allow(Submissions::EnsureAuditGenerated).to receive(:call)
  end

  it 'leaves recipients for the connector and sends nothing without SMTP' do
    allow(Dielca::CopyEmail).to receive(:smtp_available?).and_return(false)
    allow(Dielca::SignedCopyMailer).to receive(:signed_copy)
    described_class.new.perform(submitter.id)
    expect(Dielca::SignedCopyMailer).not_to have_received(:signed_copy)
    expect(submitter.reload.metadata['dielca_copy_email']).to include('status' => 'connector_pending',
                                                                      'recipients' => ['persona@example.invalid'])
  end

  it 'delivers once with SMTP and does not resend on a duplicate job' do
    allow(Dielca::CopyEmail).to receive(:smtp_available?).and_return(true)
    delivery = double
    allow(Dielca::SignedCopyMailer).to receive(:signed_copy).and_return(delivery)
    allow(delivery).to receive(:deliver_now)
    2.times { described_class.new.perform(submitter.id) }
    expect(delivery).to have_received(:deliver_now).once
    expect(submitter.reload.metadata['dielca_copy_email']).to include('status' => 'sent', 'sent_at' => be_present)
  end

  it 'marks uncertain delivery as failed without automatically resending' do
    allow(Dielca::CopyEmail).to receive(:smtp_available?).and_return(true)
    delivery = double
    allow(Dielca::SignedCopyMailer).to receive(:signed_copy).and_return(delivery)
    allow(delivery).to receive(:deliver_now).and_raise('fictitious SMTP failure')
    2.times { described_class.new.perform(submitter.id) }
    expect(delivery).to have_received(:deliver_now).once
    expect(submitter.reload.metadata['dielca_copy_email']['status']).to eq('failed')
  end

  it 'routes only BC completion copies through the new job' do
    allow(described_class).to receive(:perform_async)
    ProcessSubmitterCompletionJob.new.enqueue_completed_emails(submitter)
    expect(described_class).to have_received(:perform_async).with(submitter.id)
  end
end

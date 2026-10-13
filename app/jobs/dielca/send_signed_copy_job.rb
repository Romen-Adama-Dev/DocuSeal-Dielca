# frozen_string_literal: true

module Dielca
  class SendSignedCopyJob
    include Sidekiq::Job

    sidekiq_options retry: false

    def perform(submitter_id)
      submitter = Submitter.find(submitter_id)
      record = PdfImport.find_by!(submitter_id:, submission_id: submitter.submission_id)
      return unless submitter.submission.completed_at?

      CopyEmail.validate!(record, submitter)
      data = submitter.metadata['dielca_copy_email']
      return if data['skipped'] || data['status'].in?(%w[sending sent connector_pending failed])

      Submissions::EnsureResultGenerated.call(submitter)
      Submissions::EnsureAuditGenerated.call(submitter.submission)
      claimed = submitter.with_lock do
        data = submitter.metadata['dielca_copy_email']
        next false unless data['status'] == 'pending'

        data['status'] = CopyEmail.smtp_available? ? 'sending' : 'connector_pending'
        submitter.update!(metadata: submitter.metadata.merge('dielca_copy_email' => data))
        data['status'] == 'sending'
      end
      return unless claimed

      SignedCopyMailer.signed_copy(submitter).deliver_now
      update_status!(submitter, 'sent')
    rescue StandardError
      update_status!(submitter, 'failed') if claimed
      Rails.logger.error('DIELCA_SIGNED_COPY_FAILED')
    end

    private

    def update_status!(submitter, status)
      submitter.with_lock do
        data = submitter.metadata.fetch('dielca_copy_email').merge('status' => status)
        data['sent_at'] = Time.current.iso8601 if status == 'sent'
        submitter.update!(metadata: submitter.metadata.merge('dielca_copy_email' => data))
      end
    end
  end
end

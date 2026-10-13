# frozen_string_literal: true

module Dielca
  module CompletionCopy
    def enqueue_completed_emails(submitter)
      if PdfImport.table_exists? && PdfImport.exists?(submitter_id: submitter.id,
                                                      submission_id: submitter.submission_id)
        SendSignedCopyJob.perform_async(submitter.id)
      else
        super
      end
    end
  end
end

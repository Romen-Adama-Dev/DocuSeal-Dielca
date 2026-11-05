# frozen_string_literal: true

Rails.application.config.filter_parameters += %i[pdf signer_name personal_id customer_name customer authorized_signers signing_token sign_url signing_url values primary_email additional_emails customerEmail customer_email]

Rails.application.config.to_prepare do
  singleton = Submitters::SubmitValues.singleton_class
  singleton.prepend(Dielca::SignedIdentity) unless singleton.ancestors.include?(Dielca::SignedIdentity)
  SubmitFormUploadController.prepend(Dielca::SignatureUploadGuard) unless SubmitFormUploadController.ancestors.include?(Dielca::SignatureUploadGuard)
  ProcessSubmitterCompletionJob.prepend(Dielca::CompletionCopy) unless ProcessSubmitterCompletionJob.ancestors.include?(Dielca::CompletionCopy)
end

Rails.application.config.to_prepare do
  generator = Submissions::GenerateResultAttachments.singleton_class
  generator.prepend(Dielca::StampLogo) unless generator.ancestors.include?(Dielca::StampLogo)
end

# BC routing/employee provenance is private operational data, not request logs.
Rails.application.config.filter_parameters += %i[location_code locationCode channel route_id routeId
                                                 route_description routeDescription requested_by requestedBy]

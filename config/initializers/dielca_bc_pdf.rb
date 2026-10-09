# frozen_string_literal: true

Rails.application.config.filter_parameters += %i[pdf signer_name customer_name customer authorized_signers signing_token sign_url signing_url values]

Rails.application.config.to_prepare do
  singleton = Submitters::SubmitValues.singleton_class
  singleton.prepend(Dielca::SignedIdentity) unless singleton.ancestors.include?(Dielca::SignedIdentity)
end

# frozen_string_literal: true

Rails.application.config.filter_parameters += %i[pdf signer_name customer_name sign_url signing_url]

Rails.application.config.to_prepare do
  singleton = Submitters::SubmitValues.singleton_class
  singleton.prepend(Dielca::SignedIdentity) unless singleton.ancestors.include?(Dielca::SignedIdentity)
end

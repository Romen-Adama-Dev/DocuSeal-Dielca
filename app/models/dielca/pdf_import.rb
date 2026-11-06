# frozen_string_literal: true

module Dielca
  class PdfImport < ApplicationRecord
    attribute :authorized_signers, :string, default: -> { [] }
    attribute :customer_data, :string, default: -> { {} }
    serialize :authorized_signers, coder: JSON
    serialize :customer_data, coder: JSON
    validates :signer_mode, inclusion: { in: %w[authorized free selectable] }

    def free_signing?
      signer_mode == 'free' || (signer_mode == 'selectable' && selected_signer_id == 'other')
    end

    def signer_selection
      return 'other' if free_signing?

      'authorized' if selected_signer_id.present?
    end

    belongs_to :account
    belongs_to :submission
    belongs_to :submitter

    validates :request_id, :pdf_sha256, :fingerprint, :name_field_uuid, presence: true
  end
end

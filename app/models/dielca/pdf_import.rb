# frozen_string_literal: true

module Dielca
  class PdfImport < ApplicationRecord
    belongs_to :account
    belongs_to :submission
    belongs_to :submitter

    validates :request_id, :pdf_sha256, :fingerprint, :name_field_uuid, presence: true
  end
end

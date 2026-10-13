# frozen_string_literal: true

module Dielca
  module SignatureUploadGuard
    def authorize_upload!
      super
      return if performed? || !params[:type].in?(%w[signature initials]) || !PdfImport.table_exists?

      record = PdfImport.find_by(submitter_id: @submitter.id, submission_id: @submitter.submission_id)
      return unless record
      return if SigningConfirmation.ready?(record, @submitter)

      render json: { error: 'Valide su DNI/NIE y confirme la copia antes de firmar.' }, status: :unprocessable_content
    end
  end
end

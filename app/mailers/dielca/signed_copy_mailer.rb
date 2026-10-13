# frozen_string_literal: true

module Dielca
  class SignedCopyMailer < SubmitterMailer
    def signed_copy(submitter)
      @submitter = submitter
      @current_account = submitter.account
      data = submitter.metadata.fetch('dielca_copy_email')
      types = { 'SalesOrder' => 'Pedido', 'PostedShipment' => 'Albarán', 'PostedInvoice' => 'Factura' }
      type = types.fetch(submitter.metadata['document_type'], 'Documento')
      number = (submitter.metadata['document_number'].presence || submitter.submission.name).to_s.gsub(/[\r\n]/, ' ')
      documents = submitter.documents.to_a
      audit = submitter.submission.audit_trail
      raise 'SIGNED_ATTACHMENTS_MISSING' if documents.empty? || audit.blank?

      documents.each_with_index do |document, index|
        attachments["documento-firmado-#{index + 1}.pdf"] = document.download
      end
      attachments['auditoria.pdf'] = audit.download
      assign_message_metadata('dielca_signed_copy', submitter)
      mail(to: data.fetch('primary'), bcc: data.fetch('additional', []).uniq - [data['primary']],
           from: from_address_for_submitter(submitter), subject: "Documento firmado: #{type} #{number}")
    end
  end
end

# frozen_string_literal: true

module Dielca
  module CopyEmail
    module_function

    def required?(record)
      record.customer_data['copy_email_required'] != false
    end

    def proposed(record)
      person = record.authorized_signers.find { |item| item['id'] == record.selected_signer_id }
      person&.dig('email').presence || record.customer_data['email'].to_s
    end

    def normalize(value)
      value.to_s.strip.downcase
    end

    def valid?(value)
      value.is_a?(String) && value.length.between?(3, 254) && value.exclude?("\r") && value.exclude?("\n") &&
        value.match?(/\A[^\s<>@,;]+@[^\s<>@,;]+\.[^\s<>@,;]+\z/)
    end

    def confirm!(record, submitter, params)
      if params[:copy_choice] == 'none'
        raise Submitters::SubmitValues::ValidationError, 'La copia por correo es obligatoria.' if required?(record)

        data = { 'confirmed' => true, 'skipped' => true, 'recipients' => [], 'status' => 'skipped' }
      else
        unless params[:primary_email].is_a?(String)
          raise Submitters::SubmitValues::ValidationError, 'Indique un correo válido para la copia.'
        end

        primary = normalize(params[:primary_email])
        extras = params[:additional_emails] || []
        unless extras.is_a?(Array) && extras.size <= 4 && extras.all?(String)
          raise Submitters::SubmitValues::ValidationError, 'Máximo cinco destinatarios.'
        end

        extras = extras.map { |email| normalize(email) }.compact_blank
        unless valid?(primary) && extras.all? { |email| valid?(email) }
          raise Submitters::SubmitValues::ValidationError, 'Indique un correo válido para la copia.'
        end

        data = { 'confirmed' => true, 'skipped' => false, 'primary' => primary,
                 'changed' => primary != normalize(proposed(record)), 'additional' => extras,
                 'recipients' => ([primary] + extras).uniq, 'status' => 'pending' }
      end
      data['confirmed_at'] = Time.current.iso8601
      submitter.metadata = submitter.metadata.merge('dielca_copy_email' => data)
    end

    def validate!(record, submitter)
      data = submitter.metadata['dielca_copy_email'] || {}
      valid = data['confirmed'] == true &&
              if data['skipped'] == true
                !required?(record) && data['recipients'] == []
              else
                data['recipients'].is_a?(Array) && data['recipients'].size.between?(1, 5) &&
                  data['recipients'].all? { |email| valid?(email) }
              end
      return if valid

      raise Submitters::SubmitValues::ValidationError,
            'Confirme los destinatarios de la copia antes de firmar.'
    end

    def smtp_available?
      ENV['SMTP_ADDRESS'].present? || EncryptedConfig.exists?(key: EncryptedConfig::EMAIL_SMTP_KEY)
    end
  end
end

# frozen_string_literal: true

module Dielca
  module PdfLayout
    module_function

    def fields(template, document_uuid:, page:, role_uuid:, signer_mode: 'authorized')
      raise PdfSubmission::Error.new('LAYOUT_INVALID') unless template.submitters.size == 1

      role = template.submitters.first
      raise PdfSubmission::Error.new('LAYOUT_INVALID') if role['is_viewer'] || role['optional']

      specs = { 'Nombre' => 'text', 'DNI/NIF' => 'text', 'Firma' => 'signature' }
      raise PdfSubmission::Error.new('LAYOUT_INVALID') unless template.fields.size == specs.size

      specs.map do |name, type|
        matches = template.fields.select { |f| f['name'] == name }
        raise PdfSubmission::Error.new('LAYOUT_INVALID') unless matches.size == 1

        source = matches.first
        if source['type'] != type || source['submitter_uuid'] != role['uuid'] || source['areas'].blank?
          raise PdfSubmission::Error.new('LAYOUT_INVALID')
        end

        # Copy only placement; do not inherit defaults, conditions or validation scripts.
        areas = source['areas'].map do |area|
          coordinates = area.slice('x', 'y', 'w', 'h')
          validate_coordinates!(coordinates)
          coordinates.merge('attachment_uuid' => document_uuid, 'page' => page)
        end

        { 'uuid' => SecureRandom.uuid, 'name' => name, 'type' => type,
          'submitter_uuid' => role_uuid, 'required' => true, 'readonly' => type == 'text' && signer_mode == 'authorized',
          'preferences' => {}, 'areas' => areas }
      end
    end

    def validate_coordinates!(coordinates)
      valid = coordinates.size == 4 && coordinates.values.all? { |n| n.is_a?(Numeric) && n.finite? }
      if valid
        x, y, w, h = coordinates.values_at('x', 'y', 'w', 'h')
        valid = x >= 0 && y >= 0 && w.positive? && h.positive? && x + w <= 1 && y + h <= 1
      end
      raise PdfSubmission::Error.new('LAYOUT_INVALID') unless valid
    end
  end
end

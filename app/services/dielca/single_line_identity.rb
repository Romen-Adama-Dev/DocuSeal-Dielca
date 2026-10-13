# frozen_string_literal: true

module Dielca
  module SingleLineIdentity
    module_function

    def fit!(submitter)
      fields = (submitter.submission.template_fields || submitter.template.fields).deep_dup
      texts = fields.select { |field| field.dig('preferences', 'dielca_single_line') }
      return if texts.empty?

      attachment = submitter.submission.schema_documents.first
      pdf = HexaPDF::Document.new(io: StringIO.new(attachment.download))
      font = pdf.fonts.add('Helvetica', custom_encoding: true)
      texts.each { |field| fit_field!(field, submitter.values.fetch(field['uuid']).to_s, pdf, font) }
      submitter.submission.update!(template_fields: fields)
    end

    def fit_field!(field, value, pdf, font)
      raise Submitters::SubmitValues::ValidationError, 'El nombre debe ocupar una sola línea.' if value.match?(/[\r\n]/)

      area = field.fetch('areas').first
      page = pdf.pages[area.fetch('page')]
      page.rotate(0, flatten: true) if page[:Rotate] != 0
      width = (area.fetch('w') * page.box.width) - 1
      height = area.fetch('h') * page.box.height
      size = field.dig('preferences', 'font_size').to_i
      size -= 1 while size > 1 && !fits?(value, font, size, width, height)
      unless fits?(value, font, size, width, height)
        raise Submitters::SubmitValues::ValidationError, 'El nombre no cabe en la caja de firma configurada.'
      end

      field['preferences']['font_size'] = size
    end

    def fits?(value, font, size, width, height)
      text = HexaPDF::Layout::TextFragment.create(value.tr("\u00A0", ' '), font:, font_size: size,
                                                                           line_height: size * 1.5)
      lines = HexaPDF::Layout::TextLayouter.new(font:, font_size: size).fit([text], width, height).lines
      lines.size == 1 && text.width <= width && lines.sum(&:height) <= height
    end
  end
end

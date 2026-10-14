# frozen_string_literal: true

module Dielca
  module ReportLayout
    module_function

    PAPER_SIZES = { 'A5' => [419.53, 595.28], 'A4' => [595.28, 841.89] }.freeze

    def for_page(profile, page_size)
      return profile unless profile.key?('paper_sizes')

      unless page_size.is_a?(Array) && page_size.size == 2 &&
             page_size.all? { |value| value.is_a?(Numeric) && value.finite? && value.positive? }
        raise PdfSubmission::Error, 'PDF_GEOMETRY_INVALID'
      end

      dimensions = page_size.sort
      format = PAPER_SIZES.find do |_name, size|
        dimensions.zip(size).all? { |actual, expected| (actual - expected).abs <= 3 }
      end&.first
      selector = profile.fetch('paper_sizes')[format]
      raise PdfSubmission::Error, 'REPORT_LAYOUT_NOT_CONFIGURED' unless selector

      selected = load(report_id: selector.fetch('report_id'), document_type: '')
      raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID' if selected.nil? || selected.key?('paper_sizes')

      selected
    rescue KeyError, NoMethodError, TypeError
      raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID'
    end

    def load(report_id:, document_type:)
      return if report_id.blank? && document_type.blank?

      path = ENV['DIELCA_BC_LAYOUTS_FILE'].presence || Rails.root.join('config/dielca_bc_layouts.json')
      config = JSON.parse(File.read(path))
      profile = config.fetch('reports', {})[report_id.to_s] || config.fetch('document_types', {})[document_type]
      raise PdfSubmission::Error, 'REPORT_LAYOUT_NOT_CONFIGURED' unless profile

      profile
    rescue JSON::ParserError, Errno::ENOENT, TypeError
      raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID'
    end

    def fields(profile, document_uuid:, page:, role_uuid:, signer_mode:)
      box = profile.fetch('box').slice('x', 'y', 'w', 'h')
      PdfLayout.validate_coordinates!(box)
      specs = { 'Nombre' => 'text', 'DNI/NIF' => 'text', 'Firma' => 'signature' }
      areas = []
      result = specs.map do |name, type|
        settings = profile.fetch('fields').fetch(name)
        local = settings.slice('x', 'y', 'w', 'h')
        PdfLayout.validate_coordinates!(local)
        areas << local
        size = settings['font_size'] || 8
        raise PdfSubmission::Error, 'LAYOUT_INVALID' unless size.is_a?(Numeric) && size.between?(4, 16)

        area = { 'x' => box['x'] + (local['x'] * box['w']), 'y' => box['y'] + (local['y'] * box['h']),
                 'w' => local['w'] * box['w'], 'h' => local['h'] * box['h'],
                 'page' => page, 'attachment_uuid' => document_uuid }
        { 'uuid' => SecureRandom.uuid, 'name' => name, 'type' => type, 'required' => true,
          'readonly' => type == 'text' && signer_mode == 'authorized', 'submitter_uuid' => role_uuid,
          'areas' => [area], 'preferences' => { 'font_size' => size, 'font' => 'Helvetica', 'align' => 'left',
                                                'valign' => 'center', 'dielca_single_line' => type == 'text' } }
      end
      if areas.combination(2).any? { |first, second| overlap?(first, second) }
        raise PdfSubmission::Error, 'LAYOUT_FIELDS_OVERLAP'
      end

      result
    rescue KeyError, NoMethodError, TypeError
      raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID'
    end

    def overlap?(first, second)
      first['x'] < second['x'] + second['w'] && second['x'] < first['x'] + first['w'] &&
        first['y'] < second['y'] + second['h'] && second['y'] < first['y'] + first['h']
    end
  end
end

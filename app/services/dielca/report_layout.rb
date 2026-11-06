# frozen_string_literal: true

module Dielca
  module ReportLayout
    module_function

    NOT_CONFIGURED_MESSAGE = 'No hay un perfil de firma configurado para este informe de Business Central ' \
                             'o para el tamaño de página del PDF. Solicita configurar el perfil y vuelve a intentarlo.'

    PAPER_SIZES = { 'A5' => [419.53, 595.28], 'A4' => [595.28, 841.89] }.freeze

    def for_page(profile, page_size, text_objects: nil)
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

      select_variant(resolve_selector(selector), text_objects)
    rescue KeyError, NoMethodError, TypeError
      raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID'
    end

    def resolve_selector(selector)
      selected = if selector.key?('profile_id')
                   configuration.fetch('profiles', {})[selector['profile_id']]
                 elsif selector.key?('report_id')
                   load(report_id: selector['report_id'], document_type: '')
                 else
                   selector
                 end
      unless selected.is_a?(Hash) && selected['box'].is_a?(Hash) && selected['fields'].is_a?(Hash) &&
             !selected.key?('paper_sizes')
        raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID'
      end

      selected
    end

    def select_variant(profile, text_objects)
      return profile if profile['variants'].blank? || text_objects.nil?

      matches = profile['variants'].select do |variant|
        anchors = variant.fetch('anchors')
        raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID' if anchors.empty?

        anchors.all? { |anchor| text_objects.any? { |object| anchor_matches?(anchor, object) } }
      end
      raise PdfSubmission::Error, 'REPORT_LAYOUT_NOT_CONFIGURED' if matches.size > 1

      matches.empty? ? profile : resolve_selector(matches.sole)
    end

    def anchor_matches?(anchor, object)
      PdfLayout.validate_coordinates!(anchor.slice('x', 'y', 'w', 'h'))
      text = anchor.fetch('text')
      raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID' if text.blank?

      object.content.unicode_normalize(:nfkc).downcase.include?(text.unicode_normalize(:nfkc).downcase) &&
        object.x.between?(anchor['x'], anchor['x'] + anchor['w']) &&
        object.y.between?(anchor['y'], anchor['y'] + anchor['h'])
    end

    def load(report_id:, document_type:)
      return if report_id.blank? && document_type.blank?

      config = configuration
      profile = if report_id.present?
                  config.fetch('reports', {})[report_id.to_s]
                else
                  config.fetch('document_types', {})[document_type]
                end
      raise PdfSubmission::Error, 'REPORT_LAYOUT_NOT_CONFIGURED' unless profile

      profile
    rescue JSON::ParserError, Errno::ENOENT, TypeError
      raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID'
    end

    def configuration
      path = ENV['DIELCA_BC_LAYOUTS_FILE'].presence || Rails.root.join('config/dielca_bc_layouts.json')
      JSON.parse(File.read(path))
    rescue JSON::ParserError, Errno::ENOENT, TypeError
      raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID'
    end

    def fields(profile, document_uuid:, page:, role_uuid:, signer_mode:)
      box = profile.fetch('box').slice('x', 'y', 'w', 'h')
      PdfLayout.validate_coordinates!(box)
      specs = { 'Nombre' => 'text', 'DNI/NIF' => 'text', 'Firma' => 'signature' }
      specs['Fecha y hora de firma'] = 'text' if profile['signed_at']
      result = specs.map do |name, type|
        timestamp = name == 'Fecha y hora de firma'
        settings = timestamp ? profile.fetch('signed_at') : profile.fetch('fields').fetch(name)
        local = settings.slice('x', 'y', 'w', 'h')
        PdfLayout.validate_coordinates!(local)
        size = settings['font_size'] || 8
        raise PdfSubmission::Error, 'LAYOUT_INVALID' unless size.is_a?(Numeric) && size.between?(4, 16)

        area = page_area(box, local, document_uuid:, page:)
        { 'uuid' => SecureRandom.uuid, 'name' => name, 'type' => type, 'required' => !timestamp,
          'readonly' => timestamp || (type == 'text' && signer_mode != 'free'), 'submitter_uuid' => role_uuid,
          'areas' => [area], 'preferences' => preferences(size, type, timestamp, settings) }
      end
      attach_logo!(result, profile, box, document_uuid:, page:)

      result
    rescue KeyError, NoMethodError, TypeError
      raise PdfSubmission::Error, 'LAYOUT_CONFIGURATION_INVALID'
    end

    def page_area(box, local, document_uuid:, page:)
      { 'x' => box['x'] + (local['x'] * box['w']), 'y' => box['y'] + (local['y'] * box['h']),
        'w' => local['w'] * box['w'], 'h' => local['h'] * box['h'],
        'page' => page, 'attachment_uuid' => document_uuid }
    end

    def attach_logo!(fields, profile, box, document_uuid:, page:)
      areas = fields.flat_map { |field| field.fetch('areas') }
      if profile['logo']
        local = profile.fetch('logo').slice('x', 'y', 'w', 'h')
        PdfLayout.validate_coordinates!(local)
        area = page_area(box, local, document_uuid:, page:)
        fields.find { |field| field['type'] == 'signature' }['preferences']['dielca_stamp_logo'] = area
        areas << area
      end
      return unless areas.combination(2).any? { |first, second| overlap?(first, second) }

      raise PdfSubmission::Error, 'LAYOUT_FIELDS_OVERLAP'
    end

    def preferences(size, type, timestamp, settings)
      valign = settings.fetch('valign', 'center')
      raise PdfSubmission::Error, 'LAYOUT_INVALID' unless %w[top center bottom].include?(valign)

      { 'font_size' => size, 'font' => 'Helvetica', 'align' => 'left', 'valign' => valign,
        'dielca_single_line' => type == 'text' && !timestamp, 'dielca_signing_timestamp' => timestamp,
        'dielca_timestamp_single_line' => timestamp && settings['format'] == 'single_line' }
    end

    def overlap?(first, second)
      first['x'] < second['x'] + second['w'] && second['x'] < first['x'] + first['w'] &&
        first['y'] < second['y'] + second['h'] && second['y'] < first['y'] + first['h']
    end
  end
end

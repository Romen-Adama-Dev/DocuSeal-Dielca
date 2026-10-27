# frozen_string_literal: true

module Dielca
  module StampLogo
    ASSET_PATH = Rails.public_path.join('dielca/logo.png').freeze

    def generate_pdfs(submitter)
      pdfs = super
      fields = submitter.submission.template_fields || submitter.template.fields
      areas = fields.filter_map { |field| field.dig('preferences', 'dielca_stamp_logo') }
      return pdfs if areas.empty?
      return pdfs unless PdfImport.exists?(submission_id: submitter.submission_id, submitter_id: submitter.id)

      areas.each do |area|
        StampLogo.draw!(pdfs.fetch(area.fetch('attachment_uuid')), area)
      end
      pdfs
    end

    def self.draw!(pdf, area)
      page = pdf.pages[area.fetch('page')]
      image = pdf.images.add(ASSET_PATH.to_s)
      width = area.fetch('w') * page.box.width
      height = area.fetch('h') * page.box.height
      scale = [width / image[:Width], height / image[:Height]].min
      drawn_width = image[:Width] * scale
      drawn_height = image[:Height] * scale
      x = (area.fetch('x') * page.box.width) + ((width - drawn_width) / 2)
      y = page.box.height - (area.fetch('y') * page.box.height) - height + ((height - drawn_height) / 2)
      page.canvas(type: :overlay).image(image, at: [x, y], width: drawn_width, height: drawn_height)
    end
  end
end

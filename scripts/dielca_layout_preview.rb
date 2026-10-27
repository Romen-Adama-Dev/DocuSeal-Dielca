# frozen_string_literal: true

# Run only in an isolated test/development environment. No customer data or database writes.
# bundle exec rails runner scripts/dielca_layout_preview.rb
raise 'Use test or development' unless Rails.env.local?

report_id = ENV.fetch('PREVIEW_REPORT_ID', '50000')
size = { 'A5' => [595.28, 419.53], 'A4' => [595.28, 841.89] }.fetch(ENV.fetch('PREVIEW_PAPER_SIZE', 'A5'))
profile = Dielca::ReportLayout.load(report_id:, document_type: '')
profile = Dielca::ReportLayout.for_page(profile, size)
fields = Dielca::ReportLayout.fields(profile, document_uuid: 'demo', page: 0, role_uuid: 'demo', signer_mode: 'free')
pdf = HexaPDF::Document.new
page = pdf.pages.add([0, 0, *size])
canvas = page.canvas
width = page.box.width
height = page.box.height
canvas.font('Helvetica', size: 12)
title = { '50001' => 'FACTURA FICTICIA', '50002' => 'PEDIDO FICTICIO' }.fetch(report_id, 'ALBARAN FICTICIO')
canvas.text("#{title} - REVISION DEL DISENO", at: [190, height - 28])
canvas.font('Helvetica', size: 8)
canvas.text('ARTICULO         DENOMINACION                                      UNIDADES', at: [30, height - 148])
canvas.text('DEMO             Producto ficticio                                     1', at: [30, height - 168])
# Reproduce anonymous footer labels; these belong to the sample, not the importer.
if report_id == '50002'
  canvas.rectangle(210.5, 77.5, 179.9, 94.8).stroke
  canvas.font('Helvetica', size: 7)
  canvas.text('CONFORME CLIENTE (FIRMA Y SELLO)', at: [216, 164])
  canvas.text('Nombre: ____________  DNI: __________  Fecha:', at: [216, 82])
elsif report_id == '50000' && ENV['PREVIEW_PAPER_SIZE'] == 'A4'
  canvas.rectangle(28, 74.89, 363, 17).stroke
  canvas.font('Helvetica', size: 6)
  canvas.text('RECIBI CONFORME', at: [32, 81])
  canvas.text('Nombre / cargo:', at: [104, 81])
  canvas.text('DNI:', at: [207.85, 81])
  canvas.text('Fecha:', at: [262.73, 81])
  canvas.text('Firma:', at: [312, 81])
else
  canvas.rectangle(0.048 * width, 0.119 * height, 0.254 * width, 0.209 * height).stroke
  canvas.rectangle(0.302 * width, 0.119 * height, 0.378 * width, 0.209 * height).stroke
  canvas.rectangle(0.680 * width, 0.119 * height, 0.262 * width, 0.209 * height).stroke
  canvas.font('Helvetica', size: 6)
  canvas.text('BASE IMPONIBLE       %         CUOTA', at: [0.052 * width, 0.298 * height])
  canvas.text('100,00              7,00        7,00', at: [0.085 * width, 0.270 * height])
  canvas.text('TEXTO CENTRAL DEL INFORME', at: [0.33 * width, 0.215 * height])
  canvas.text('TOTAL: 107,00', at: [0.72 * width, 0.215 * height])
end
demo_values = { 'Nombre' => 'Persona Demo', 'DNI/NIF' => '12345678Z',
                'Fecha y hora de firma' => "01/11/2026\n14:05:06" }
fields.each do |field|
  area = field['areas'].first
  x = area['x'] * width
  y = height - ((area['y'] + area['h']) * height)
  if field['type'] == 'text'
    text = demo_values.fetch(field['name'])
    if field.dig('preferences', 'dielca_single_line')
      Dielca::SingleLineIdentity.fit_field!(field, text, pdf, pdf.fonts.add('Helvetica', custom_encoding: true))
    end
    size = field.dig('preferences', 'font_size')
    canvas.font('Helvetica', size:)
    valign = field.dig('preferences', 'valign').to_sym
    font = pdf.fonts.add('Helvetica', custom_encoding: true)
    fragment = HexaPDF::Layout::TextFragment.create(text, font:, font_size: size, line_height: size * 1.5)
    layouter = HexaPDF::Layout::TextLayouter.new(text_valign: valign, text_align: :left, font:, font_size: size)
    margin = valign == :bottom ? 0 : 1
    layouter.fit([fragment], area['w'] * width, area['h'] * height)
            .draw(canvas, x + 1, height - (area['y'] * height) - margin)
  else
    canvas.line(x + 2, y + 5, x + (area['w'] * width * 0.45), y + (area['h'] * height * 0.78))
          .line(x + (area['w'] * width * 0.45), y + (area['h'] * height * 0.78), x + 10, y + 4)
          .line(x + 10, y + 4, x + (area['w'] * width) - 2, y + 12).stroke
  end
end
fields.filter_map { |field| field.dig('preferences', 'dielca_stamp_logo') }.each do |area|
  Dielca::StampLogo.draw!(pdf, area)
end
pdf.write(ENV.fetch('PREVIEW_OUTPUT', '/tmp/dielca-layout-preview.pdf'))

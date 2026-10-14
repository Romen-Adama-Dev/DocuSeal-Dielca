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
title = report_id == '50001' ? 'FACTURA FICTICIA' : 'ALBARAN FICTICIO'
canvas.text("#{title} - REVISION DEL DISENO", at: [190, height - 28])
canvas.font('Helvetica', size: 8)
canvas.text('ARTICULO         DENOMINACION                                      UNIDADES', at: [30, height - 148])
canvas.text('DEMO             Producto ficticio                                     1', at: [30, height - 168])
# Reproduce only the anonymous footer boxes needed for review.
canvas.rectangle(0.048 * width, 0.126 * height, 0.254 * width, 0.202 * height).stroke
canvas.rectangle(0.302 * width, 0.126 * height, 0.378 * width, 0.202 * height).stroke
canvas.rectangle(0.680 * width, 0.126 * height, 0.262 * width, 0.202 * height).stroke
canvas.font('Helvetica', size: 6)
canvas.text('BASE IMPONIBLE       %         CUOTA', at: [0.052 * width, 0.298 * height])
canvas.text('100,00              7,00        7,00', at: [0.085 * width, 0.270 * height])
canvas.text('TEXTO CENTRAL DEL INFORME', at: [0.33 * width, 0.215 * height])
canvas.text('TOTAL: 107,00', at: [0.72 * width, 0.215 * height])
fields.each do |field|
  area = field['areas'].first
  x = area['x'] * width
  y = height - ((area['y'] + area['h']) * height)
  if field['type'] == 'text'
    text = field['name'] == 'Nombre' ? 'Persona ficticia de prueba' : '12345678Z'
    canvas.font('Helvetica', size: field.dig('preferences', 'font_size'))
    canvas.text(text, at: [x + 1, y + (area['h'] * height / 2) - 1.5])
  else
    canvas.line(x + 2, y + 5, x + (area['w'] * width * 0.45), y + (area['h'] * height * 0.78))
          .line(x + (area['w'] * width * 0.45), y + (area['h'] * height * 0.78), x + 10, y + 4)
          .line(x + 10, y + 4, x + (area['w'] * width) - 2, y + 12).stroke
  end
end
pdf.write(ENV.fetch('PREVIEW_OUTPUT', '/tmp/dielca-layout-preview.pdf'))

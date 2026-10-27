# frozen_string_literal: true

RSpec.describe Dielca::ReportLayout do
  let(:shipment) { described_class.load(report_id: '50000', document_type: 'PostedShipment') }
  let(:profile) { described_class.for_page(shipment, [595.28, 419.53]) }

  def fields(config = profile, page: 0)
    described_class.fields(config, document_uuid: 'fictitious-pdf', page:, role_uuid: 'fictitious-role',
                                   signer_mode: 'free')
  end

  it 'uses the report before the document type and falls back to a configured type' do
    expect(described_class.load(report_id: '50000', document_type: 'SalesOrder')).to eq(shipment)
    expect(described_class.load(report_id: '99999', document_type: 'PostedShipment')).to eq(shipment)
    expect(described_class.load(report_id: '', document_type: '')).to be_nil
  end

  %w[59999].each do |report|
    it "refuses unmeasured report #{report} instead of stamping a guessed box" do
      expect { described_class.load(report_id: report, document_type: '') }
        .to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('REPORT_LAYOUT_NOT_CONFIGURED') }
    end
  end

  it 'uses shipment placement for A5 invoices and the edited invoice placement for A4' do
    invoice = described_class.load(report_id: '50001', document_type: 'PostedInvoice')
    expect(described_class.for_page(invoice, [595.28, 419.53])).to eq(profile)
    expect(described_class.for_page(invoice, [420, 595])).to eq(profile)
    edited = invoice['paper_sizes']['A4']
    expect(described_class.for_page(invoice, [595.28, 841.89])).to eq(edited)
    expect(described_class.for_page(invoice, [842, 595])).to eq(edited)
    expect(fields(edited, page: 2).first(3).map { |field| field['areas'].first.slice('x', 'y', 'w', 'h') }).to eq([
      { 'x' => 0.08219512195121952, 'y' => 0.8133804714530541, 'w' => 0.28853658536585364, 'h' => 0.019033321650394175 },
      { 'x' => 0.08219512195121952, 'y' => 0.8395723077918018, 'w' => 0.28853658536585364, 'h' => 0.019033321650394175 },
      { 'x' => 0.395609756097561, 'y' => 0.834, 'w' => 0.28439024390243905, 'h' => 0.03565 }
    ])
    expect(described_class.for_page(profile, [595.28, 419.53])).to eq(profile)
  end

  it 'puts the A4 shipment timestamp after the footer Fecha label, separate from identity and signature' do
    config = described_class.for_page(shipment, [595.276, 841.89])
    result = fields(config, page: 2)
    expect(result.pluck('name')).to eq(['Nombre', 'DNI/NIF', 'Firma', 'Fecha y hora de firma'])
    timestamp = result.last
    expect(timestamp).to include('readonly' => true, 'required' => false)
    expect(timestamp.dig('preferences', 'font_size')).to eq(4)
    area = timestamp['areas'].first
    expect(area['x'] * 595.276).to be > 284.13
    expect((area['x'] + area['w']) * 595.276).to be < 311
    expect(area['y'] * 841.89).to be >= 750
    expect((area['y'] + area['h']) * 841.89).to be <= 767
    expect(result.flat_map { |field| field['areas'] }.pluck('page')).to all(eq(2))
    areas = result.flat_map { |field| field['areas'] }
    expect(areas.combination(2).any? { |first, second| described_class.overlap?(first, second) }).to be(false)
    expect(result.map { |field| field['areas'].first.values_at('y', 'h') }.uniq).to eq([[0.8915, 0.0175]])
    expect(config).not_to have_key('logo') # No room for a second logo in this narrow printed row.
  end

  it 'refuses unsupported invoice paper sizes and invalid geometry' do
    invoice = described_class.load(report_id: '50001', document_type: 'PostedInvoice')
    expect { described_class.for_page(invoice, [612, 792]) }
      .to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('REPORT_LAYOUT_NOT_CONFIGURED') }
    expect { described_class.for_page(invoice, [Float::NAN, 595]) }
      .to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('PDF_GEOMETRY_INVALID') }
    expect { described_class.for_page(invoice, nil) }
      .to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('PDF_GEOMETRY_INVALID') }
  end

  it 'refuses missing references and recursive paper selectors' do
    expect { described_class.for_page({ 'paper_sizes' => { 'A5' => {} } }, [595, 420]) }
      .to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('LAYOUT_CONFIGURATION_INVALID') }
    expect { described_class.for_page({ 'paper_sizes' => { 'A5' => { 'report_id' => '50001' } } }, [595, 420]) }
      .to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('LAYOUT_CONFIGURATION_INVALID') }
  end

  it 'uses the latest approved order rectangles and a server-owned timestamp on the last page' do
    config = described_class.load(report_id: '50002', document_type: 'SalesOrder')
    expect(described_class.load(report_id: '99999', document_type: 'SalesOrder')).to eq(config)
    result = fields(config, page: 2)
    expected = [
      { 'x' => 0.41, 'y' => 0.874, 'w' => 0.0778048780487805, 'h' => 0.02 },
      { 'x' => 0.5231707317073171, 'y' => 0.874, 'w' => 0.06707317073170727, 'h' => 0.02 },
      { 'x' => 0.363, 'y' => 0.843, 'w' => 0.2834146341463415, 'h' => 0.0275 }
    ]
    expect(result.first(3).map { |field| field['areas'].first.slice('x', 'y', 'w', 'h') }).to eq(expected)
    expect(result.flat_map { |field| field['areas'] }.pluck('page')).to all(eq(2))
    timestamp = result.last
    expect(timestamp).to include('name' => 'Fecha y hora de firma', 'required' => false, 'readonly' => true)
    expect(timestamp['preferences']).to include('dielca_signing_timestamp' => true, 'dielca_single_line' => false)
    text_fields = result.select { |field| field['type'] == 'text' }
    expect(text_fields.map { |field| field['areas'].first.values_at('y', 'h') }.uniq).to eq([[0.874, 0.02]])
    expect(text_fields.map { |field| field.dig('preferences', 'valign') }).to all(eq('bottom'))
    expect(text_fields.map { |field| field.dig('preferences', 'font_size') }).to all(eq(6))
    rectangles = result.flat_map { |field| field['areas'] }
    expect(rectangles.combination(2).any? { |first, second| described_class.overlap?(first, second) }).to be(false)
  end

  it 'contains all three nonoverlapping fields below taxes inside the left box' do
    result = fields(page: 2)
    expect(result.pluck('name')).to eq(['Nombre', 'DNI/NIF', 'Firma', 'Fecha y hora de firma'])
    result.each do |field|
      area = field['areas'].first
      expect(area).to include('page' => 2, 'attachment_uuid' => 'fictitious-pdf')
      expect(area['x']).to be >= 0.047
      expect(area['x'] + area['w']).to be <= 0.301001
      expect(area['y']).to be >= 0.788
      expect(area['y'] + area['h']).to be <= 0.881
    end
    signature = result.find { |field| field['type'] == 'signature' }['areas'].first
    expect(signature['y'] + signature['h']).to be < result.first.dig('areas', 0, 'y')
  end

  it 'includes a server-owned timestamp for every configured report, format and document fallback' do
    { '50000' => 'PostedShipment', '50001' => 'PostedInvoice', '50002' => 'SalesOrder' }.each do |report, type|
      report_profile = described_class.load(report_id: report, document_type: type)
      expect(described_class.load(report_id: '', document_type: type)).to eq(report_profile)
      sizes = report_profile.key?('paper_sizes') ? [[595.28, 419.53], [595.28, 841.89]] : [[595.28, 841.89]]
      sizes.each do |size|
        result = fields(described_class.for_page(report_profile, size), page: 2)
        timestamp = result.find { |field| field.dig('preferences', 'dielca_signing_timestamp') }
        expect(timestamp).to include('readonly' => true, 'required' => false)
        expect(timestamp['areas'].first['page']).to eq(2)
      end
    end
  end

  it 'rejects overlapping fields and out-of-page boxes' do
    overlap = profile.deep_dup
    overlap['fields']['Firma'] = overlap['fields']['Nombre'].deep_dup
    expect { fields(overlap) }.to raise_error(Dielca::PdfSubmission::Error) do |error|
      expect(error.code).to eq('LAYOUT_FIELDS_OVERLAP')
    end
    outside = profile.deep_dup
    outside['box']['x'] = 0.01
    expect { fields(outside) }.to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('LAYOUT_INVALID') }
  end

  it 'keeps the logo separate from the signature and identity rectangles' do
    result = fields(page: 2)
    logo = result.find { |field| field['type'] == 'signature' }.dig('preferences', 'dielca_stamp_logo')
    expect(logo).to include('attachment_uuid' => 'fictitious-pdf', 'page' => 2)
    expect(result.flat_map { |field| field['areas'] }.none? { |area| described_class.overlap?(logo, area) }).to be(true)
    invalid = profile.deep_dup
    invalid['logo'] = invalid['fields']['Firma'].slice('x', 'y', 'w', 'h')
    expect { fields(invalid) }.to raise_error(Dielca::PdfSubmission::Error) do |error|
      expect(error.code).to eq('LAYOUT_FIELDS_OVERLAP')
    end
    legacy = profile.except('logo')
    expect(fields(legacy).any? { |field| field.dig('preferences', 'dielca_stamp_logo') }).to be(false)
  end

  it 'rejects unknown vertical alignment values' do
    invalid = profile.deep_dup
    invalid['fields']['Nombre']['valign'] = 'arbitrary'
    expect { fields(invalid) }.to raise_error(Dielca::PdfSubmission::Error) do |error|
      expect(error.code).to eq('LAYOUT_INVALID')
    end
  end

  it 'fails closed for an invalid configuration file' do
    previous = ENV.fetch('DIELCA_BC_LAYOUTS_FILE', nil)
    ENV['DIELCA_BC_LAYOUTS_FILE'] = '/no-such-fictitious-layout.json'
    expect { shipment }.to raise_error(Dielca::PdfSubmission::Error) do |error|
      expect(error.code).to eq('LAYOUT_CONFIGURATION_INVALID')
    end
  ensure
    previous ? ENV['DIELCA_BC_LAYOUTS_FILE'] = previous : ENV.delete('DIELCA_BC_LAYOUTS_FILE')
  end
end

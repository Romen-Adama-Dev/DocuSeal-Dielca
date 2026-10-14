# frozen_string_literal: true

RSpec.describe Dielca::ReportLayout do
  let(:profile) { described_class.load(report_id: '50000', document_type: 'PostedShipment') }

  def fields(config = profile, page: 0)
    described_class.fields(config, document_uuid: 'fictitious-pdf', page:, role_uuid: 'fictitious-role',
                                   signer_mode: 'free')
  end

  it 'uses the report before the document type and falls back to a configured type' do
    expect(described_class.load(report_id: '50000', document_type: 'SalesOrder')).to eq(profile)
    expect(described_class.load(report_id: '99999', document_type: 'PostedShipment')).to eq(profile)
    expect(described_class.load(report_id: '', document_type: '')).to be_nil
  end

  %w[59999].each do |report|
    it "refuses unmeasured report #{report} instead of stamping a guessed box" do
      expect { described_class.load(report_id: report, document_type: '') }
        .to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('REPORT_LAYOUT_NOT_CONFIGURED') }
    end
  end

  it 'uses shipment placement for A5 invoices and order placement for A4 invoices' do
    invoice = described_class.load(report_id: '50001', document_type: 'PostedInvoice')
    expect(described_class.for_page(invoice, [595.28, 419.53])).to eq(profile)
    expect(described_class.for_page(invoice, [420, 595])).to eq(profile)
    order = described_class.load(report_id: '50002', document_type: 'SalesOrder')
    expect(described_class.for_page(invoice, [595.28, 841.89])).to eq(order)
    expect(described_class.for_page(invoice, [842, 595])).to eq(order)
    expect(described_class.for_page(profile, [595.28, 419.53])).to eq(profile)
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

  it 'preserves the approved order placement on the last page' do
    config = described_class.load(report_id: '50002', document_type: 'SalesOrder')
    expect(described_class.load(report_id: '99999', document_type: 'SalesOrder')).to eq(config)
    result = fields(config, page: 2)
    expect(result.map { |field| field['areas'].first.slice('x', 'y', 'w', 'h', 'page') }).to eq([
      { 'x' => 0.09, 'y' => 0.792, 'w' => 0.55, 'h' => 0.018, 'page' => 2 },
      { 'x' => 0.09, 'y' => 0.832, 'w' => 0.22, 'h' => 0.019, 'page' => 2 },
      { 'x' => 0.34, 'y' => 0.815, 'w' => 0.33, 'h' => 0.05, 'page' => 2 }
    ])
  end

  it 'contains all three nonoverlapping fields below taxes inside the left box' do
    result = fields(page: 2)
    expect(result.pluck('name')).to eq(['Nombre', 'DNI/NIF', 'Firma'])
    result.each do |field|
      area = field['areas'].first
      expect(area).to include('page' => 2, 'attachment_uuid' => 'fictitious-pdf')
      expect(area['x']).to be >= 0.055
      expect(area['x'] + area['w']).to be <= 0.300001
      expect(area['y']).to be >= 0.765
      expect(area['y'] + area['h']).to be <= 0.860001
    end
    expect(result.last.dig('areas', 0, 'x')).to be > result.first.dig('areas', 0, 'x')
  end

  it 'rejects overlapping fields and out-of-page boxes' do
    overlap = profile.deep_dup
    overlap['fields']['Firma'] = overlap['fields']['Nombre'].deep_dup
    expect { fields(overlap) }.to raise_error(Dielca::PdfSubmission::Error) do |error|
      expect(error.code).to eq('LAYOUT_FIELDS_OVERLAP')
    end
    outside = profile.deep_dup
    outside['box']['x'] = 0.99
    expect { fields(outside) }.to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('LAYOUT_INVALID') }
  end

  it 'fails closed for an invalid configuration file' do
    previous = ENV.fetch('DIELCA_BC_LAYOUTS_FILE', nil)
    ENV['DIELCA_BC_LAYOUTS_FILE'] = '/no-such-fictitious-layout.json'
    expect { profile }.to raise_error(Dielca::PdfSubmission::Error) do |error|
      expect(error.code).to eq('LAYOUT_CONFIGURATION_INVALID')
    end
  ensure
    previous ? ENV['DIELCA_BC_LAYOUTS_FILE'] = previous : ENV.delete('DIELCA_BC_LAYOUTS_FILE')
  end
end

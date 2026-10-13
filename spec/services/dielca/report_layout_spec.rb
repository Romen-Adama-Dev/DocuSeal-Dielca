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

  %w[50001 50002].each do |report|
    it "refuses unmeasured report #{report} instead of stamping a guessed box" do
      expect { described_class.load(report_id: report, document_type: '') }
        .to raise_error(Dielca::PdfSubmission::Error) { |error| expect(error.code).to eq('REPORT_LAYOUT_NOT_CONFIGURED') }
    end
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

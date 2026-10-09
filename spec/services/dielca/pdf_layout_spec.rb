# frozen_string_literal: true

RSpec.describe Dielca::PdfLayout do
  let(:fields) do
    { 'Nombre' => 'text', 'DNI/NIF' => 'text', 'Firma' => 'signature' }.map do |name, type|
      { 'name' => name, 'type' => type, 'submitter_uuid' => 'source-role',
        'default_value' => 'must not be inherited',
        'areas' => [{ 'x' => 0.1, 'y' => 0.6, 'w' => 0.3, 'h' => 0.1, 'page' => 0 }] }
    end
  end
  let(:layout) { double(submitters: [{ 'uuid' => 'source-role' }], fields:) }

  it 'uses approved coordinates on the new final page and drops defaults' do
    result = described_class.fields(layout, document_uuid: 'new-document', page: 16, role_uuid: 'new-role')
    expect(result).to all(include('submitter_uuid' => 'new-role', 'required' => true, 'readonly' => false))
    expect(result.flat_map { |f| f['areas'] }).to all(include('page' => 16, 'attachment_uuid' => 'new-document'))
    expect(result).to all(satisfy { |f| !f.key?('default_value') })
  end

  it 'rejects out-of-page placement' do
    fields.first['areas'].first['x'] = 0.9
    expect do
      described_class.fields(layout, document_uuid: 'new', page: 0, role_uuid: 'new')
    end.to raise_error(Dielca::PdfSubmission::Error, 'LAYOUT_INVALID')
  end

  it 'rejects duplicate field names' do
    fields[1]['name'] = 'Nombre'
    expect do
      described_class.fields(layout, document_uuid: 'new', page: 0, role_uuid: 'new')
    end.to raise_error(Dielca::PdfSubmission::Error, 'LAYOUT_INVALID')
  end
end

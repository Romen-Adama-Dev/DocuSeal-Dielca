# frozen_string_literal: true

RSpec.describe Dielca::DocumentAccess do
  let(:policy) { described_class.new(locations: ['SITE TEST']) }
  let(:metadata) do
    { 'bc_original_pdf' => true, 'location_code' => 'SITE TEST',
      'document_type' => 'PostedShipment', 'report_id' => '50000', 'channel' => 'Delivery' }
  end

  def allowed(role, data = metadata, action = :view, status = 'ReadyToSign')
    policy.allowed?(groups: ["#{described_class::GROUP_PREFIX}#{role}"], metadata: data, action:, status:)
  end

  it 'allows supported sales documents for counter staff in their exact warehouse' do
    described_class::TYPES.each do |type|
      %w[Counter Delivery].each do |channel|
        expect(allowed('Mostrador', metadata.merge('document_type' => type, 'report_id' => described_class::REPORTS[type], 'channel' => channel))).to be(true)
      end
    end
    expect(allowed('Mostrador', metadata.merge('location_code' => 'site test'))).to be(false)
    expect(allowed('Mostrador', metadata, :administer)).to be(false)
  end

  it 'requires an application role and refuses unsupported documents and arbitrary actions' do
    expect(policy.allowed?(groups: ['Admins'], metadata:, action: :view, status: 'ReadyToSign')).to be(false)
    expect(allowed('Admins', metadata.merge('document_type' => 'SalesQuote'))).to be(false)
    expect(allowed('Admins', metadata, :unknown)).to be(false)
    expect(allowed('Admins', metadata.except('bc_original_pdf'))).to be(false)
  end

  it 'restricts historical and unmapped warehouses to explicit application admins' do
    [nil, '', 'UNKNOWN SITE'].each do |location|
      data = metadata.merge('location_code' => location)
      expect(allowed('Admins', data)).to be(true)
      expect(allowed('Mostrador', data)).to be(false)
      expect(allowed('Reparto', data)).to be(false)
    end
  end

  it 'lets delivery staff read and sign every delivery document of their site, nothing else' do
    expect(allowed('Reparto')).to be(true)
    expect(allowed('Reparto', metadata, :open_signing)).to be(true)
    expect(allowed('Reparto', metadata, :download_pdf)).to be(true)
    expect(allowed('Reparto', metadata.merge('channel' => 'Counter'))).to be(false)
    expect(allowed('Reparto', metadata.merge('location_code' => 'OTHER'))).to be(false)
    %w[SalesOrder PostedInvoice].each do |type|
      other = metadata.merge('document_type' => type, 'report_id' => described_class::REPORTS[type])
      expect(allowed('Reparto', other)).to be(false)
    end
    %i[prepare retry copy archive administer].each do |action|
      expect(allowed('Reparto', metadata, action, 'PendingProcessing')).to be(false)
      expect(allowed('Reparto', metadata, action)).to be(false)
    end
    expect(allowed('Reparto', metadata, :open_signing, 'Signed')).to be(false)
  end

  it 'never allows another signature on a completed document or an inconsistent report' do
    %w[Admins Mostrador].each do |role|
      expect(allowed(role, metadata, :open_signing, 'Signed')).to be(false)
      expect(allowed(role, metadata, :prepare, 'Signed')).to be(false)
      expect(allowed(role, metadata, :download_audit, 'Signed')).to be(true)
      expect(allowed(role, metadata.merge('report_id' => '50001'))).to be(false)
      expect(allowed(role, metadata, :view, 'unknown')).to be(false)
    end
    expect(allowed('Admins', metadata, :retry, 'Error')).to be(true)
    expect(allowed('Admins', metadata, :retry, 'Signed')).to be(false)
  end

  it 'reads a private server mapping file and denies access if it disappears' do
    previous = ENV['DIELCA_BC_SITE_LOCATIONS_FILE']
    file = Tempfile.new('fictitious-sites')
    file.write({ 'el-sebadal' => ['SITE TEST'] }.to_json)
    file.close
    ENV['DIELCA_BC_SITE_LOCATIONS_FILE'] = file.path
    groups = [described_class::GROUP_PREFIX + 'Mostrador']
    expect(described_class.from_env.allowed?(groups:, metadata:, action: :view, status: 'ReadyToSign')).to be(true)
    file.unlink
    expect(described_class.from_env.allowed?(groups:, metadata:, action: :view, status: 'ReadyToSign')).to be(false)
  ensure
    file&.close!
    previous.nil? ? ENV.delete('DIELCA_BC_SITE_LOCATIONS_FILE') : ENV['DIELCA_BC_SITE_LOCATIONS_FILE'] = previous
  end

  it 'fails closed for missing or malformed server mappings' do
    previous = ENV['DIELCA_BC_SITE_LOCATIONS']
    previous_file = ENV.delete('DIELCA_BC_SITE_LOCATIONS_FILE')
    ['{}', 'invalid', '[]', '{"el-sebadal":"SITE TEST"}'].each do |value|
      ENV['DIELCA_BC_SITE_LOCATIONS'] = value
      expect(described_class.from_env.allowed?(groups: [described_class::GROUP_PREFIX + 'Admins'], metadata:,
                                              action: :view, status: 'ReadyToSign')).to be(false)
    end
  ensure
    previous.nil? ? ENV.delete('DIELCA_BC_SITE_LOCATIONS') : ENV['DIELCA_BC_SITE_LOCATIONS'] = previous
    ENV['DIELCA_BC_SITE_LOCATIONS_FILE'] = previous_file if previous_file
  end
end

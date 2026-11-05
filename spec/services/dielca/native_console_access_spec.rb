# frozen_string_literal: true

RSpec.describe Dielca::NativeConsoleAccess do
  %w[Admins Mostrador Reparto].each do |role|
    it "does not let business #{role} grant native console access" do
      group = "DIELCA/FirmasInformes/ElSebadal/#{role}"
      expect(described_class.allowed?([group], ['Admins', group])).to be(false)
    end
  end

  it 'preserves existing global console admins without making that a business role' do
    expect(described_class.allowed?(['Admins'], ['Admins'])).to be(true)
    expect(described_class.allowed?(['Admins', 'DIELCA/FirmasInformes/ElSebadal/Reparto'], ['Admins'])).to be(true)
  end

  it 'denies an empty configuration and malformed group claims' do
    expect(described_class.allowed?(['anything'], [])).to be(false)
    [nil, 'Admins', { 'role' => 'admin' }, [nil], [123]].each do |value|
      expect(described_class.allowed?(value, ['Admins'])).to be(false)
    end
  end

  it 'rejects business-only provisioning before looking up or creating a native user' do
    previous_domains = ENV.fetch('DOCUSEAL_OIDC_ALLOWED_DOMAINS', nil)
    previous_groups = ENV.fetch('DOCUSEAL_OIDC_ALLOWED_GROUPS', nil)
    ENV['DOCUSEAL_OIDC_ALLOWED_DOMAINS'] = 'example.invalid'
    ENV['DOCUSEAL_OIDC_ALLOWED_GROUPS'] = 'DIELCA/FirmasInformes/ElSebadal/Mostrador'
    expect(User).not_to receive(:find_by)
    claims = { 'email' => 'fictitious-oidc-user@example.invalid',
               'groups' => ['DIELCA/FirmasInformes/ElSebadal/Mostrador'] }
    expect { AuthentikOidcController.new.send(:find_or_provision_user!, claims) }
      .to raise_error(AuthentikOidc::Error, 'OIDC user is not in an allowed group')
  ensure
    previous_domains ? ENV['DOCUSEAL_OIDC_ALLOWED_DOMAINS'] = previous_domains : ENV.delete('DOCUSEAL_OIDC_ALLOWED_DOMAINS')
    previous_groups ? ENV['DOCUSEAL_OIDC_ALLOWED_GROUPS'] = previous_groups : ENV.delete('DOCUSEAL_OIDC_ALLOWED_GROUPS')
  end
end

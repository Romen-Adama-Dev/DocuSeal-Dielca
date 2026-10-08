# frozen_string_literal: true

RSpec.describe 'Authentik OIDC' do
  around do |example|
    values = {
      DOCUSEAL_OIDC_ENABLED: 'true',
      DOCUSEAL_OIDC_ISSUER: 'https://auth.example.test/application/o/docuseal',
      DOCUSEAL_OIDC_CLIENT_ID: 'docuseal',
      DOCUSEAL_OIDC_CLIENT_SECRET: 'secret',
      DOCUSEAL_OIDC_REDIRECT_URI: 'https://firmas.example.test/auth/authentik/callback',
      DOCUSEAL_OIDC_ALLOWED_DOMAINS: 'dielca.com',
      DOCUSEAL_OIDC_ALLOWED_GROUPS: 'Admins'
    }.transform_keys(&:to_s)
    previous = values.to_h { |key, _value| [key, ENV[key]] }
    values.each { |key, value| ENV[key] = value }
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it 'starts authorization with state, nonce and PKCE' do
    stub_request(:get, 'https://auth.example.test/application/o/docuseal/.well-known/openid-configuration')
      .to_return(status: 200, body: {
        issuer: 'https://auth.example.test/application/o/docuseal',
        authorization_endpoint: 'https://auth.example.test/authorize',
        token_endpoint: 'https://auth.example.test/token',
        jwks_uri: 'https://auth.example.test/jwks'
      }.to_json)

    get authentik_oidc_path

    expect(response).to redirect_to(%r{\Ahttps://auth\.example\.test/authorize\?})
    query = Rack::Utils.parse_query(URI.parse(response.location).query)
    expect(query).to include(
      'client_id' => 'docuseal',
      'response_type' => 'code',
      'scope' => 'openid profile email',
      'code_challenge_method' => 'S256'
    )
    expect(query.values_at('state', 'nonce', 'code_challenge')).to all(be_present)
  end

  it 'rejects a callback without a valid state' do
    get authentik_oidc_callback_path, params: { code: 'code', state: 'wrong' }

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq('No se pudo iniciar sesión con DIELCA.')
  end
end

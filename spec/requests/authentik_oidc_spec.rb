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

  describe 'callback' do
    let(:prefix) { 'DIELCA/FirmasInformes/ElSebadal/' }
    let(:console_paths) { %w[/submissions /templates /templates/new /settings/users] }

    before { create(:user) }

    def login_with(groups:, email: 'empleado@dielca.com')
      stub_request(:get, 'https://auth.example.test/application/o/docuseal/.well-known/openid-configuration')
        .to_return(status: 200, body: {
          issuer: 'https://auth.example.test/application/o/docuseal',
          authorization_endpoint: 'https://auth.example.test/authorize',
          token_endpoint: 'https://auth.example.test/token',
          jwks_uri: 'https://auth.example.test/jwks'
        }.to_json)
      allow_any_instance_of(AuthentikOidc).to receive(:claims_for).and_return(
        'email' => email, 'name' => 'Empleado Prueba', 'groups' => groups
      )
      get authentik_oidc_path
      state = Rack::Utils.parse_query(URI.parse(response.location).query)['state']
      get authentik_oidc_callback_path, params: { code: 'code', state: }
    end

    %w[Reparto Mostrador Admins].each do |role|
      it "signs #{role} into an empty business portal without a native user" do
        expect { login_with(groups: ["#{prefix}#{role}"]) }.not_to change(User, :count)

        expect(response).to redirect_to(dielca_portal_path)
        follow_redirect!
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('No tienes documentos disponibles.')

        console_paths.each do |path|
          get path
          expect(response).to redirect_to(new_user_session_path)
        end
      end
    end

    it 'keeps console admins on the native console even with a business role' do
      login_with(groups: ['Admins', "#{prefix}Reparto"], email: 'consola@dielca.com')

      expect(response).to redirect_to(root_path)
      expect(User.find_by(email: 'consola@dielca.com')).to be_present
    end

    it 'drops a previous admin session when another identity is rejected' do
      login_with(groups: ['Admins'], email: 'consola@dielca.com')
      get '/templates'
      expect(response).to have_http_status(:ok)

      login_with(groups: ['DIELCA/Delegaciones/El Sebadal'], email: 'otro@dielca.com')
      expect(response).to redirect_to(new_user_session_path)
      get '/templates'
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'drops a previous admin session when a business role signs in' do
      login_with(groups: ['Admins'], email: 'consola@dielca.com')
      login_with(groups: ["#{prefix}Reparto"])

      expect(response).to redirect_to(dielca_portal_path)
      get '/templates'
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'rejects users without a console or business group' do
      login_with(groups: ['DIELCA/Delegaciones/El Sebadal'])

      expect(response).to redirect_to(new_user_session_path)
      get dielca_portal_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'rejects business users from other domains' do
      login_with(groups: ["#{prefix}Reparto"], email: 'externo@example.com')

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'closes the business session' do
      login_with(groups: ["#{prefix}Reparto"])
      delete dielca_portal_session_path

      expect(response).to redirect_to(new_user_session_path)
      get dielca_portal_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'expires the business session' do
      login_with(groups: ["#{prefix}Mostrador"])

      travel(Dielca::BusinessSession::TTL + 1.minute) do
        get dielca_portal_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end

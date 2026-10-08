# frozen_string_literal: true

require 'base64'
require 'digest'
require 'json'
require 'jwt'
require 'openssl'
require 'securerandom'
require 'uri'

class AuthentikOidc
  class Error < StandardError; end

  STATE_TTL = 10.minutes
  HTTP_TIMEOUT = 10

  attr_reader :issuer, :client_id, :client_secret, :redirect_uri

  def initialize
    @issuer = ENV.fetch('DOCUSEAL_OIDC_ISSUER').to_s.chomp('/')
    @client_id = ENV.fetch('DOCUSEAL_OIDC_CLIENT_ID')
    @client_secret = ENV.fetch('DOCUSEAL_OIDC_CLIENT_SECRET')
    @redirect_uri = ENV.fetch('DOCUSEAL_OIDC_REDIRECT_URI')

    raise Error, 'OIDC issuer must use HTTPS' unless URI.parse(@issuer).is_a?(URI::HTTPS)
    raise Error, 'OIDC redirect URI must use HTTPS' unless URI.parse(@redirect_uri).is_a?(URI::HTTPS)
  rescue KeyError, URI::InvalidURIError => e
    raise Error, e.message
  end

  def authorization_url(state:, nonce:, code_challenge:)
    query = URI.encode_www_form(
      client_id:,
      redirect_uri:,
      response_type: 'code',
      scope: 'openid profile email',
      state:,
      nonce:,
      code_challenge:,
      code_challenge_method: 'S256'
    )

    "#{discovery.fetch('authorization_endpoint')}?#{query}"
  end

  def claims_for(code:, code_verifier:, nonce:)
    response = connection.post(discovery.fetch('token_endpoint')) do |request|
      request.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      request.body = URI.encode_www_form(
        grant_type: 'authorization_code',
        code:,
        redirect_uri:,
        client_id:,
        client_secret:,
        code_verifier:
      )
    end
    raise Error, 'OIDC token exchange failed' unless response.success?

    token = JSON.parse(response.body).fetch('id_token')
    decode_and_verify(token, nonce:)
  rescue Faraday::Error
    raise Error, 'OIDC token endpoint was unavailable'
  rescue JSON::ParserError, KeyError
    raise Error, 'OIDC response was incomplete'
  end

  def self.code_challenge(verifier)
    Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
  end

  private

  def discovery
    @discovery ||= begin
      response = connection.get("#{issuer}/.well-known/openid-configuration")
      raise Error, 'OIDC discovery failed' unless response.success?

      document = JSON.parse(response.body)
      raise Error, 'OIDC issuer mismatch' unless secure_compare(document.fetch('issuer').to_s.chomp('/'), issuer)

      document
    rescue Faraday::Error
      raise Error, 'OIDC discovery endpoint was unavailable'
    rescue JSON::ParserError, KeyError
      raise Error, 'OIDC discovery was invalid'
    end
  end

  def decode_and_verify(token, nonce:)
    header = JWT.decode(token, nil, false).last
    raise Error, 'OIDC signing algorithm is not allowed' unless header['alg'] == 'RS256'

    jwk = jwks.fetch('keys').find { |candidate| candidate['kid'] == header['kid'] }
    raise Error, 'OIDC signing key was not found' unless jwk

    key = JWT::JWK.import(jwk).public_key
    claims = JWT.decode(
      token,
      key,
      true,
      algorithms: ['RS256'],
      iss: discovery.fetch('issuer'),
      verify_iss: true,
      aud: client_id,
      verify_aud: true
    ).first
    raise Error, 'OIDC nonce mismatch' unless secure_compare(claims['nonce'].to_s, nonce)

    claims
  rescue JWT::DecodeError, JWT::JWKError, OpenSSL::PKey::PKeyError => e
    raise Error, "OIDC token validation failed: #{e.class}"
  end

  def jwks
    @jwks ||= begin
      response = connection.get(discovery.fetch('jwks_uri'))
      raise Error, 'OIDC keys could not be loaded' unless response.success?

      JSON.parse(response.body)
    rescue Faraday::Error
      raise Error, 'OIDC key endpoint was unavailable'
    rescue JSON::ParserError, KeyError
      raise Error, 'OIDC key response was invalid'
    end
  end

  def connection
    @connection ||= Faraday.new(request: { timeout: HTTP_TIMEOUT, open_timeout: HTTP_TIMEOUT })
  end

  def secure_compare(left, right)
    left.bytesize == right.bytesize && ActiveSupport::SecurityUtils.secure_compare(left, right)
  end
end

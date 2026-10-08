# frozen_string_literal: true

class AuthentikOidcController < ApplicationController
  skip_before_action :maybe_redirect_to_setup
  skip_before_action :authenticate_user!
  skip_authorization_check

  def new
    return head :not_found unless oidc_enabled?

    state = SecureRandom.urlsafe_base64(32)
    nonce = SecureRandom.urlsafe_base64(32)
    verifier = SecureRandom.urlsafe_base64(64)
    session[:docuseal_oidc] = {
      'state' => state,
      'nonce' => nonce,
      'verifier' => verifier,
      'created_at' => Time.current.to_i
    }

    redirect_to oidc.authorization_url(
      state:,
      nonce:,
      code_challenge: AuthentikOidc.code_challenge(verifier)
    ), allow_other_host: true
  rescue AuthentikOidc::Error => e
    oidc_failure(e)
  end

  def create
    return head :not_found unless oidc_enabled?

    oidc_session = session.delete(:docuseal_oidc) || {}
    validate_callback!(oidc_session)
    claims = oidc.claims_for(
      code: params.require(:code),
      code_verifier: oidc_session.fetch('verifier'),
      nonce: oidc_session.fetch('nonce')
    )
    user = find_or_provision_user!(claims)
    sign_in(user)

    redirect_to root_path, notice: 'Sesión iniciada con DIELCA.'
  rescue AuthentikOidc::Error, ActionController::ParameterMissing, KeyError, ActiveRecord::RecordInvalid => e
    oidc_failure(e)
  end

  private

  def oidc_enabled?
    ENV['DOCUSEAL_OIDC_ENABLED'] == 'true'
  end

  def oidc
    @oidc ||= AuthentikOidc.new
  end

  def validate_callback!(oidc_session)
    created_at = Time.zone.at(Integer(oidc_session.fetch('created_at')))
    raise AuthentikOidc::Error, 'OIDC state expired' if created_at < AuthentikOidc::STATE_TTL.ago

    expected = oidc_session.fetch('state').to_s
    received = params.require(:state).to_s
    valid = expected.bytesize == received.bytesize && ActiveSupport::SecurityUtils.secure_compare(expected, received)
    raise AuthentikOidc::Error, 'OIDC state mismatch' unless valid
  rescue ArgumentError
    raise AuthentikOidc::Error, 'OIDC state was invalid'
  end

  def find_or_provision_user!(claims)
    email = claims['email'].to_s.strip.downcase
    domains = ENV.fetch('DOCUSEAL_OIDC_ALLOWED_DOMAINS', 'dielca.com').split(',').map { |item| item.strip.downcase }
    domain = email.split('@', 2).last
    raise AuthentikOidc::Error, 'OIDC email is not permitted' if email.blank? || !domains.include?(domain)

    allowed_groups = ENV.fetch('DOCUSEAL_OIDC_ALLOWED_GROUPS', 'Admins').split(',').map(&:strip).reject(&:blank?)
    user_groups = Array(claims['groups']).map(&:to_s)
    if allowed_groups.present? && (allowed_groups & user_groups).empty?
      raise AuthentikOidc::Error, 'OIDC user is not in an allowed group'
    end

    user = User.find_by(email:)
    raise AuthentikOidc::Error, 'DocuSeal user is archived' if user&.archived_at?

    first_name, last_name = names_from(claims)
    if user
      user.update!(first_name:, last_name:)
      return user
    end

    account = User.active.order(:id).first&.account
    raise AuthentikOidc::Error, 'DocuSeal account is not initialized' unless account

    account.users.create!(
      email:,
      first_name:,
      last_name:,
      password: SecureRandom.base58(48),
      confirmed_at: Time.current
    )
  end

  def names_from(claims)
    full_name = claims['name'].to_s.squish
    given_name = claims['given_name'].to_s.squish
    family_name = claims['family_name'].to_s.squish

    if family_name.blank? && full_name.present?
      parts = full_name.split
      return [parts.shift.to_s, parts.join(' ')]
    end

    [given_name.presence || full_name, family_name]
  end

  def oidc_failure(error)
    Rails.logger.warn("Authentik OIDC login failed: #{error.class}")
    redirect_to new_user_session_path, alert: 'No se pudo iniciar sesión con DIELCA.'
  end
end

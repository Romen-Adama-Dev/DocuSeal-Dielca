# frozen_string_literal: true

module Dielca
  # Login-only session for business roles (Admins/Mostrador/Reparto of Firmas).
  # It never creates or signs in a native DocuSeal user, so it grants no console,
  # template, submission or download access. Document listings will be added
  # behind Dielca::DocumentAccess once the business entry is integrated.
  module BusinessSession
    KEY = :dielca_business
    TTL = 8.hours
    LABELS = { admin: 'Administración', mostrador: 'Mostrador', reparto: 'Reparto' }.freeze

    module_function

    def role_for(groups)
      return unless groups.is_a?(Array) && groups.all?(String)

      DocumentAccess::ROLES.find { |suffix, _| groups.include?(DocumentAccess::GROUP_PREFIX + suffix) }&.last
    end

    def build(email:, name:, role:)
      { 'email' => email, 'name' => name.to_s.first(120), 'role' => role.to_s, 'at' => Time.current.to_i }
    end

    def current(session)
      data = session[KEY]
      return unless data.is_a?(Hash) && LABELS.key?(data['role'].to_s.to_sym)
      return if Time.zone.at(data['at'].to_i) < TTL.ago

      data
    end
  end
end

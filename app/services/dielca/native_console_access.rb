# frozen_string_literal: true

module Dielca
  module NativeConsoleAccess
    module_function

    # Business roles must never provision an unrestricted native DocuSeal admin,
    # including if someone accidentally puts them in the OIDC console allowlist.
    def allowed?(groups, configured_groups)
      return false unless groups.is_a?(Array) && groups.all?(String)

      console_groups = configured_groups.reject { |group| group.start_with?('DIELCA/FirmasInformes/') }
      console_groups.present? && (console_groups & groups).present?
    end
  end
end

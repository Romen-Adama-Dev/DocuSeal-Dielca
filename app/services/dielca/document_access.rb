# frozen_string_literal: true

module Dielca
  # Business portal policy. Does not grant access to the native admin console.
  # Call only with freshly verified server-side groups and connector metadata.
  class DocumentAccess
    GROUP_PREFIX = 'DIELCA/FirmasInformes/ElSebadal/'
    ROLES = { 'Admins' => :admin, 'Mostrador' => :mostrador, 'Reparto' => :reparto }.freeze
    TYPES = %w[SalesOrder PostedShipment PostedInvoice].freeze
    REPORTS = { 'SalesOrder' => '50002', 'PostedShipment' => '50000', 'PostedInvoice' => '50001' }.freeze
    STATES = %w[PendingProcessing ReadyToSign Signed Archived Error].freeze
    READ = %i[view open_signing download_pdf download_audit].freeze
    ACTIONS = (READ + %i[prepare retry archive copy administer]).freeze

    # JSON mapping resides in a protected server environment/secret, never assets.
    def self.from_env
      path = ENV['DIELCA_BC_SITE_LOCATIONS_FILE'].presence
      source = path ? File.read(path, 10_001) : ENV.fetch('DIELCA_BC_SITE_LOCATIONS', '{}')
      return new(locations: []) if source.bytesize > 10_000

      mapping = JSON.parse(source)
      new(locations: mapping.fetch('el-sebadal', []))
    rescue JSON::ParserError, TypeError, NoMethodError, SystemCallError, IOError
      new(locations: [])
    end

    def initialize(locations:)
      @locations = if locations.is_a?(Array) && locations.all? { |v| v.is_a?(String) && v.present? && v.length <= 20 && !v.match?(/[[:cntrl:]]/) }
                     locations.dup.freeze
                   else
                     []
                   end
    end

    def allowed?(groups:, metadata:, action:, status:)
      return false unless groups.is_a?(Array) && groups.all?(String) && metadata.is_a?(Hash)
      return false unless ACTIONS.include?(action) && @locations.present?

      role = ROLES.find { |suffix, _| groups.include?(GROUP_PREFIX + suffix) }&.last
      return false unless role && TYPES.include?(metadata['document_type'])
      return false unless metadata['bc_original_pdf'] == true
      return false unless REPORTS[metadata['document_type']] == metadata['report_id'].to_s
      return false unless STATES.include?(status)
      return false if %w[Signed Archived].include?(status) && %i[prepare open_signing].include?(action)
      return false if action == :prepare && status != 'PendingProcessing'
      return false if action == :open_signing && status != 'ReadyToSign'
      return false if %i[copy archive download_audit].include?(action) && !%w[Signed Archived].include?(status)
      return false if action == :retry && status != 'Error'

      # Historical/unmapped requests require the explicit application admin.
      return false unless role == :admin || @locations.include?(metadata['location_code'])
      return true if role == :admin
      return false unless %w[Counter Delivery].include?(metadata['channel'])
      return (READ + [:prepare]).include?(action) if role == :mostrador

      # Business decision 2026-11-06: no route mapping. Delivery staff see every
      # Delivery signature of their mapped site and pick the one to sign in the
      # portal. Read-only: they never prepare, retry, copy or archive.
      # TODO: narrow to a route/carrier once business defines one.
      role == :reparto && metadata['channel'] == 'Delivery' &&
        metadata['document_type'] == 'PostedShipment' && READ.include?(action)
    end
  end
end

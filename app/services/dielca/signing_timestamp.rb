# frozen_string_literal: true

module Dielca
  module SigningTimestamp
    module_function

    TIME_ZONE = 'Atlantic/Canary'

    def assign!(submitter)
      return unless submitter.completed_at?

      fields = submitter.submission.template_fields || submitter.template.fields
      fields.each do |field|
        next unless field.dig('preferences', 'dielca_signing_timestamp') == true

        # Use the completion timestamp, never a browser-supplied clock or PDF generation time.
        submitter.values[field.fetch('uuid')] = submitter.completed_at.in_time_zone(TIME_ZONE)
                                                   .strftime("%d/%m/%Y\n%H:%M:%S")
      end
    end
  end
end

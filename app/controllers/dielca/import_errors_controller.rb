# frozen_string_literal: true

module Dielca
  class ImportErrorsController < ApplicationController
    # Static help only: no request, customer, PDF or signing capability is accepted.
    skip_before_action :authenticate_user!, :maybe_redirect_to_setup
    skip_authorization_check
    layout 'plain'

    def show
      response.headers['Cache-Control'] = 'no-store'
      render :show, status: :unprocessable_content
    end
  end
end

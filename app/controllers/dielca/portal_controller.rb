# frozen_string_literal: true

module Dielca
  class PortalController < ApplicationController
    skip_before_action :authenticate_user!, :maybe_redirect_to_setup
    skip_authorization_check
    layout 'plain'

    before_action :no_store

    def show
      @business = Dielca::BusinessSession.current(session)
      return redirect_to(new_user_session_path) unless @business

      @role_label = Dielca::BusinessSession::LABELS.fetch(@business['role'].to_sym)
    end

    def destroy
      reset_session
      redirect_to new_user_session_path, notice: 'Sesión cerrada.'
    end

    private

    def no_store
      response.headers['Cache-Control'] = 'no-store'
    end
  end
end

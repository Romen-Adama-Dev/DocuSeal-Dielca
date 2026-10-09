# frozen_string_literal: true

module Dielca
  class AuthorizedSignersController < ApplicationController
    skip_before_action :authenticate_user!
    skip_authorization_check

    def update
      # The secret signing capability is in a filtered POST body, never our URL.
      @submitter = Submitter.find_by(slug: params[:signing_token].to_s)
      unless @submitter && PdfImport.exists?(submitter_id: @submitter.id) &&
             Submitters::AuthorizedForForm.call(@submitter, current_user, request)
        return render json: { error: 'No se puede acceder a esta firma.' }, status: :forbidden
      end
      AuthorizedSignerSelection.select!(@submitter, params[:authorized_signer_id].to_s)
      respond_to do |format|
        format.json { render json: { status: 'selected' } }
        format.html { render :selected }
      end
    rescue Submitters::SubmitValues::ValidationError => error
      render json: { error: error.message }, status: :unprocessable_content
    end
  end
end

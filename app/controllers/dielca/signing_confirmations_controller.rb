# frozen_string_literal: true

module Dielca
  class SigningConfirmationsController < ApplicationController
    skip_before_action :authenticate_user!
    skip_authorization_check

    def create
      submitter = Submitter.find_by(slug: params[:signing_token].to_s)
      unless submitter && Submitters::AuthorizedForForm.call(submitter, current_user, request)
        return render json: { error: 'No se puede acceder a esta firma.' }, status: :forbidden
      end

      SigningConfirmation.confirm!(submitter, params)
      respond_to do |format|
        format.json { render json: { status: 'confirmed' } }
        format.html { redirect_to submit_form_path(submitter.slug) }
      end
    rescue ActiveRecord::RecordNotFound
      head :not_found
    rescue Submitters::SubmitValues::ValidationError => e
      render json: { error: e.message }, status: :unprocessable_content
    end
  end
end

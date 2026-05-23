# frozen_string_literal: true

class Api::V1::SliceJobsController < ApplicationController
  # POST /api/v1/print_assets/:print_asset_id/slice
  def create
    asset = current_user_asset(params[:print_asset_id])

    job = asset.slice_jobs.build(slice_job_params)
    if job.save
      SliceWorker.perform_async(job.id)
      render json: job_json(job), status: :created
    else
      render json: { errors: job.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/slice_jobs/:id
  def show
    job = current_user_job(params[:id])
    render json: job_json(job)
  end

  # GET /api/v1/slice_jobs/:id/download
  def download
    job = current_user_job(params[:id])

    unless job.completed? && job.output_gcode.attached?
      return render json: { error: "G-code not ready" }, status: :not_found
    end

    redirect_to rails_blob_url(job.output_gcode, host: ENV.fetch("APP_HOST", "http://localhost:3000")),
                allow_other_host: true
  end

  private

  include Rails.application.routes.url_helpers

  def current_user_asset(asset_id)
    PrintAsset.joins(:project)
              .where(projects: { user_id: current_user.id })
              .find(asset_id)
  end

  def current_user_job(job_id)
    SliceJob.joins(print_asset: :project)
            .where(projects: { user_id: current_user.id })
            .find(job_id)
  end

  def slice_job_params
    params.permit(:slicer, color_swaps_attributes: [:layer_number, :pause_type, :color_label])
  end

  def job_json(job)
    {
      id: job.id,
      status: job.status,
      slicer: job.slicer,
      estimated_time: job.estimated_time,
      material_used: job.material_used,
      error_message: job.error_message,
      color_swaps: job.color_swaps.as_json(only: [:id, :layer_number, :pause_type, :color_label]),
      output_gcode_url: job.output_gcode.attached? ? rails_blob_url(job.output_gcode, host: ENV.fetch("APP_HOST", "http://localhost:3000")) : nil,
      created_at: job.created_at,
      updated_at: job.updated_at
    }
  end
end

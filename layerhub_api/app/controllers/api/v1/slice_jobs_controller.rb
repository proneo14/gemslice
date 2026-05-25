# frozen_string_literal: true

class Api::V1::SliceJobsController < ApplicationController
  # POST /api/v1/print_assets/:print_asset_id/slice
  def create
    asset = current_user_asset(params[:print_asset_id])

    # Parse settings from JSON string if sent via FormData
    parsed_settings = if params[:settings].is_a?(String)
      JSON.parse(params[:settings]).with_indifferent_access
    else
      params.fetch(:settings, {})
    end

    job = asset.slice_jobs.build(slice_job_params)

    # Attach scene file if provided (combined STL with all objects + transforms)
    if params[:scene_file].present?
      job.scene_file.attach(params[:scene_file])
    end

    if job.save
      permitted = parsed_settings.slice(
        *%w[layer_height first_layer_height infill infill_pattern
            wall_count top_layers bottom_layers support support_type support_density
            brim_width skirt_loops print_speed nozzle_diameter
            bed_width bed_depth center_x center_y]
      ).to_h
      SliceWorker.perform_async(job.id, permitted)
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

  # GET /api/v1/slice_jobs/:id/gcode_text
  def gcode_text
    job = current_user_job(params[:id])

    unless job.completed? && job.output_gcode.attached?
      return render json: { error: "G-code not ready" }, status: :not_found
    end

    render plain: job.output_gcode.download
  end

  # PATCH /api/v1/slice_jobs/:id/cancel
  def cancel
    job = current_user_job(params[:id])
    unless job.completed? || job.failed?
      job.update!(status: :failed, error_message: "Cancelled by user")
    end
    render json: job_json(job)
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

  def settings_params
    params.fetch(:settings, {}).permit(
      :layer_height, :first_layer_height, :infill, :infill_pattern,
      :wall_count, :top_layers, :bottom_layers, :support, :support_density,
      :brim_width, :skirt_loops, :print_speed, :nozzle_diameter
    )
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

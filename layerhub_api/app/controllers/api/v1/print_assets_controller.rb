# frozen_string_literal: true

class Api::V1::PrintAssetsController < ApplicationController
  before_action :set_asset, only: [:show, :update, :destroy]

  # GET /api/v1/projects/:project_id/print_assets
  def index
    assets = current_project.print_assets
      .with_attached_source_file
      .order(created_at: :desc)

    render json: assets.map { |a| asset_json(a) }
  end

  # GET /api/v1/projects/:project_id/print_assets/:id
  def show
    render json: asset_json(@asset)
  end

  # POST /api/v1/projects/:project_id/print_assets
  def create
    asset = current_project.print_assets.build(asset_params)

    if asset.save
      render json: asset_json(asset), status: :created
    else
      render json: { errors: asset.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # PATCH /api/v1/projects/:project_id/print_assets/:id
  def update
    if @asset.update(asset_params)
      render json: asset_json(@asset)
    else
      render json: { errors: @asset.errors.full_messages }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/projects/:project_id/print_assets/:id
  def destroy
    @asset.destroy
    head :no_content
  end

  private

  def set_asset
    @asset = current_project.print_assets.find(params[:id])
  end

  def asset_params
    params.permit(:name, :file_type, :notes, :source_file, tag_ids: [])
  end

  def asset_json(asset)
    json = {
      id: asset.id,
      name: asset.name,
      file_type: asset.file_type,
      notes: asset.notes,
      tags: asset.tags.as_json(only: [:id, :name]),
      source_file_url: asset.source_file_url,
      created_at: asset.created_at,
      updated_at: asset.updated_at
    }

    latest = asset.slice_jobs.order(created_at: :desc).first
    if latest
      json[:latest_slice_job] = {
        id: latest.id,
        status: latest.status,
        slicer: latest.slicer,
        estimated_time: latest.estimated_time,
        material_used: latest.material_used,
        error_message: latest.error_message,
        color_swaps: latest.color_swaps.as_json(only: [:id, :layer_number, :pause_type, :color_label]),
        output_gcode_url: latest.output_gcode.attached? ? rails_blob_url(latest.output_gcode, host: ENV.fetch("APP_HOST", "http://localhost:3000")) : nil,
        created_at: latest.created_at
      }
    end

    json
  end
end

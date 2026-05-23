class PrintAsset < ApplicationRecord
  include Rails.application.routes.url_helpers

  belongs_to :project
  has_one_attached :source_file
  has_many :asset_tags, dependent: :destroy
  has_many :tags, through: :asset_tags
  # has_many :slice_jobs, dependent: :destroy  # Phase 3

  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[stl gcode 3mf], allow_blank: true }

  def source_file_url
    return nil unless source_file.attached?

    rails_blob_url(source_file, host: ENV.fetch("APP_HOST", "http://localhost:3000"))
  end
end

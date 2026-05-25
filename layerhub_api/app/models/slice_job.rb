class SliceJob < ApplicationRecord
  belongs_to :print_asset
  has_many :color_swaps, dependent: :destroy
  has_one_attached :output_gcode
  has_one_attached :scene_file

  enum :status, { pending: 0, slicing: 1, post_processing: 2, completed: 3, failed: 4 }

  accepts_nested_attributes_for :color_swaps, allow_destroy: true
end

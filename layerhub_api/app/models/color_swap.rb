class ColorSwap < ApplicationRecord
  belongs_to :slice_job

  validates :layer_number, presence: true, numericality: { greater_than: 0 }
  validates :pause_type, inclusion: { in: %w[M600 M400\ U1] }
end

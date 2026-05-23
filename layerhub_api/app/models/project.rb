class Project < ApplicationRecord
  belongs_to :user
  has_many :print_assets, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
end

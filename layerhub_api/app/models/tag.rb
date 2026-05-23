class Tag < ApplicationRecord
  has_many :asset_tags, dependent: :destroy
  has_many :print_assets, through: :asset_tags

  validates :name, presence: true, uniqueness: { case_sensitive: false }
end

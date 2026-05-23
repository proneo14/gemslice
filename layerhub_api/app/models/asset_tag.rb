class AssetTag < ApplicationRecord
  belongs_to :print_asset
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :print_asset_id }
end

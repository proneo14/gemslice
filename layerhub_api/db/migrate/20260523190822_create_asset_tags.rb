class CreateAssetTags < ActiveRecord::Migration[8.1]
  def change
    create_table :asset_tags do |t|
      t.references :print_asset, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true

      t.timestamps
    end

    add_index :asset_tags, [:print_asset_id, :tag_id], unique: true
  end
end

class CreatePrintAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :print_assets do |t|
      t.string :name
      t.string :file_type
      t.text :notes
      t.references :project, null: false, foreign_key: true

      t.timestamps
    end
  end
end

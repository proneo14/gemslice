class CreateSliceJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :slice_jobs do |t|
      t.integer :status, default: 0, null: false
      t.references :print_asset, null: false, foreign_key: true
      t.string :slicer
      t.string :estimated_time
      t.string :material_used
      t.text :error_message

      t.timestamps
    end
  end
end

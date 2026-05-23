class CreateColorSwaps < ActiveRecord::Migration[8.1]
  def change
    create_table :color_swaps do |t|
      t.references :slice_job, null: false, foreign_key: true
      t.integer :layer_number, null: false
      t.string :pause_type, default: "M400 U1", null: false
      t.string :color_label

      t.timestamps
    end
  end
end

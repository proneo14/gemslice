# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_23_210101) do
  create_schema "extensions"

  # These are extensions that must be enabled in order to support this database
  enable_extension "extensions.pg_stat_statements"
  enable_extension "extensions.pgcrypto"
  enable_extension "extensions.uuid-ossp"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vault.supabase_vault"

  create_table "public.active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "public.active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "public.active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "public.asset_tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "print_asset_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "updated_at", null: false
    t.index ["print_asset_id", "tag_id"], name: "index_asset_tags_on_print_asset_id_and_tag_id", unique: true
    t.index ["print_asset_id"], name: "index_asset_tags_on_print_asset_id"
    t.index ["tag_id"], name: "index_asset_tags_on_tag_id"
  end

  create_table "public.color_swaps", force: :cascade do |t|
    t.string "color_label"
    t.datetime "created_at", null: false
    t.integer "layer_number", null: false
    t.string "pause_type", default: "M400 U1", null: false
    t.bigint "slice_job_id", null: false
    t.datetime "updated_at", null: false
    t.index ["slice_job_id"], name: "index_color_swaps_on_slice_job_id"
  end

  create_table "public.print_assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file_type"
    t.string "name"
    t.text "notes"
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_print_assets_on_project_id"
  end

  create_table "public.projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "public.slice_jobs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "estimated_time"
    t.string "material_used"
    t.bigint "print_asset_id", null: false
    t.string "slicer"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["print_asset_id"], name: "index_slice_jobs_on_print_asset_id"
  end

  create_table "public.tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "public.users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "jti", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
  end

  add_foreign_key "public.active_storage_attachments", "public.active_storage_blobs", column: "blob_id"
  add_foreign_key "public.active_storage_variant_records", "public.active_storage_blobs", column: "blob_id"
  add_foreign_key "public.asset_tags", "public.print_assets"
  add_foreign_key "public.asset_tags", "public.tags"
  add_foreign_key "public.color_swaps", "public.slice_jobs"
  add_foreign_key "public.print_assets", "public.projects"
  add_foreign_key "public.projects", "public.users"
  add_foreign_key "public.slice_jobs", "public.print_assets"

end

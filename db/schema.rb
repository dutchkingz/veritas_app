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

ActiveRecord::Schema[8.1].define(version: 2026_03_10_120549) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "ai_analyses", force: :cascade do |t|
    t.string "anomaly_notes"
    t.bigint "article_id", null: false
    t.datetime "created_at", null: false
    t.string "geopolitical_topic"
    t.boolean "linguistic_anomaly_flag"
    t.string "sentiment_color"
    t.string "sentiment_label"
    t.string "summary"
    t.string "threat_level"
    t.float "trust_score"
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "index_ai_analyses_on_article_id"
  end

  create_table "articles", force: :cascade do |t|
    t.bigint "country_id", null: false
    t.datetime "created_at", null: false
    t.datetime "fetched_at"
    t.string "headline"
    t.float "latitude"
    t.float "longitude"
    t.datetime "published_at"
    t.jsonb "raw_data"
    t.bigint "region_id", null: false
    t.string "source_name"
    t.string "source_url"
    t.integer "target_country"
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_articles_on_country_id"
    t.index ["region_id"], name: "index_articles_on_region_id"
  end

  create_table "briefings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "generated_at"
    t.string "pdf_url"
    t.string "threat_summary"
    t.string "top_narratives"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_briefings_on_user_id"
  end

  create_table "countries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "iso_code"
    t.string "name"
    t.bigint "region_id", null: false
    t.datetime "updated_at", null: false
    t.index ["region_id"], name: "index_countries_on_region_id"
  end

  create_table "narrative_arcs", force: :cascade do |t|
    t.string "arc_color"
    t.bigint "article_id", null: false
    t.datetime "created_at", null: false
    t.string "origin_country"
    t.float "origin_lat"
    t.float "origin_lng"
    t.string "target_country"
    t.float "target_lat"
    t.float "target_lng"
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "index_narrative_arcs_on_article_id"
  end

  create_table "narrative_convergences", force: :cascade do |t|
    t.integer "article_count"
    t.datetime "calculated_at"
    t.float "convergence_percentage"
    t.datetime "created_at", null: false
    t.string "topic_keyword"
    t.datetime "updated_at", null: false
  end

  create_table "pages", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
  end

  create_table "perspective_filters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "filter_type"
    t.string "keywords"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "regions", force: :cascade do |t|
    t.integer "article_volume"
    t.datetime "created_at", null: false
    t.datetime "last_calculated_at"
    t.float "latitude"
    t.float "longitude"
    t.string "name"
    t.integer "threat_level"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "ai_analyses", "articles"
  add_foreign_key "articles", "countries"
  add_foreign_key "articles", "regions"
  add_foreign_key "briefings", "users"
  add_foreign_key "countries", "regions"
  add_foreign_key "narrative_arcs", "articles"
end

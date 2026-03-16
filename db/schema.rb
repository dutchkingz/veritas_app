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

ActiveRecord::Schema[8.1].define(version: 2026_03_13_142000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "ai_analyses", force: :cascade do |t|
    t.string "analysis_status", default: "pending"
    t.jsonb "analyst_response"
    t.string "anomaly_notes"
    t.jsonb "arbiter_response"
    t.bigint "article_id", null: false
    t.datetime "created_at", null: false
    t.string "geopolitical_topic"
    t.boolean "linguistic_anomaly_flag"
    t.string "sentiment_color"
    t.string "sentiment_label"
    t.jsonb "sentinel_response"
    t.string "summary"
    t.string "threat_level"
    t.float "trust_score"
    t.datetime "updated_at", null: false
    t.index ["article_id"], name: "index_ai_analyses_on_article_id"
  end

  create_table "articles", force: :cascade do |t|
    t.text "content"
    t.bigint "country_id", null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1536
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

  create_table "intelligence_reports", force: :cascade do |t|
    t.jsonb "analyzed_article_ids", default: []
    t.datetime "created_at", null: false
    t.bigint "region_id", null: false
    t.string "status", default: "pending", null: false
    t.text "summary"
    t.datetime "updated_at", null: false
    t.index ["region_id"], name: "index_intelligence_reports_on_region_id"
    t.index ["status"], name: "index_intelligence_reports_on_status"
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

  create_table "narrative_routes", force: :cascade do |t|
    t.float "amplification_score", default: 0.0
    t.string "arc_color"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "first_hop_at"
    t.jsonb "hops", default: [], null: false
    t.boolean "is_complete", default: false
    t.datetime "last_hop_at"
    t.float "manipulation_score", default: 0.0
    t.string "name"
    t.bigint "narrative_arc_id", null: false
    t.string "origin_country"
    t.float "origin_lat"
    t.float "origin_lng"
    t.float "propagation_speed"
    t.string "status", default: "tracking"
    t.string "target_country"
    t.float "target_lat"
    t.float "target_lng"
    t.jsonb "timeline", default: []
    t.integer "total_duration_seconds", default: 0
    t.integer "total_hops", default: 0
    t.integer "total_reach_countries", default: 0
    t.datetime "updated_at", null: false
    t.index ["first_hop_at"], name: "index_narrative_routes_on_first_hop_at"
    t.index ["is_complete"], name: "index_narrative_routes_on_is_complete"
    t.index ["last_hop_at"], name: "index_narrative_routes_on_last_hop_at"
    t.index ["manipulation_score"], name: "index_narrative_routes_on_manipulation_score"
    t.index ["narrative_arc_id"], name: "index_narrative_routes_on_narrative_arc_id"
    t.index ["origin_country", "target_country"], name: "index_narrative_routes_on_origin_country_and_target_country"
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

  create_table "saved_articles", force: :cascade do |t|
    t.bigint "article_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.string "headline"
    t.datetime "published_at"
    t.string "source_name"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["article_id"], name: "index_saved_articles_on_article_id"
    t.index ["user_id"], name: "index_saved_articles_on_user_id"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.string "role", default: "user", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "ai_analyses", "articles"
  add_foreign_key "articles", "countries"
  add_foreign_key "articles", "regions"
  add_foreign_key "briefings", "users"
  add_foreign_key "countries", "regions"
  add_foreign_key "intelligence_reports", "regions"
  add_foreign_key "narrative_arcs", "articles"
  add_foreign_key "narrative_routes", "narrative_arcs"
  add_foreign_key "saved_articles", "articles"
  add_foreign_key "saved_articles", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end

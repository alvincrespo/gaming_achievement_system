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

ActiveRecord::Schema[8.0].define(version: 2025_07_12_011655) do
  create_table "achievement_categories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.string "name"
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_achievement_categories_on_guild_id"
  end

  create_table "achievement_unlocks", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "player_id", null: false
    t.bigint "achievement_id", null: false
    t.bigint "guild_id", null: false
    t.datetime "unlocked_at"
    t.integer "progress_percentage"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["achievement_id", "player_id", "id", "deleted_at"], name: "idx_achievement_unlocks_covering_latest", order: { id: :desc }
    t.index ["achievement_id"], name: "index_achievement_unlocks_on_achievement_id"
    t.index ["guild_id"], name: "index_achievement_unlocks_on_guild_id"
    t.index ["player_id"], name: "index_achievement_unlocks_on_player_id"
  end

  create_table "achievements", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.integer "points"
    t.integer "rarity"
    t.string "icon_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "games", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.integer "genre"
    t.string "platform"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "games_achievements", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "achievement_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["achievement_id"], name: "index_games_achievements_on_achievement_id"
    t.index ["game_id"], name: "index_games_achievements_on_game_id"
  end

  create_table "gameships", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "game_id", null: false
    t.bigint "achievement_category_id", null: false
    t.bigint "guild_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["achievement_category_id"], name: "index_gameships_on_achievement_category_id"
    t.index ["game_id"], name: "index_gameships_on_game_id"
    t.index ["guild_id"], name: "index_gameships_on_guild_id"
  end

  create_table "guilds", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.text "description"
    t.string "tag"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "guildships", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "guild_id", null: false
    t.integer "guild_type"
    t.string "region"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["guild_id"], name: "index_guildships_on_guild_id"
  end

  create_table "players", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "username"
    t.string "email"
    t.integer "level"
    t.integer "total_points"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "achievement_categories", "guilds"
  add_foreign_key "achievement_unlocks", "achievements"
  add_foreign_key "achievement_unlocks", "guilds"
  add_foreign_key "achievement_unlocks", "players"
  add_foreign_key "games_achievements", "achievements"
  add_foreign_key "games_achievements", "games"
  add_foreign_key "gameships", "achievement_categories"
  add_foreign_key "gameships", "games"
  add_foreign_key "gameships", "guilds"
  add_foreign_key "guildships", "guilds"
end

class AddIndexesToAchievementUnlocks < ActiveRecord::Migration[8.0]
  def change
    add_index :achievement_unlocks,
              [ :guild_id, :deleted_at, :player_id, :achievement_id, :id ],
              name: 'idx_covering_guild_deleted_at_player_achievement',
              order: { id: :desc }
  end

  def down
    remove_index :achievement_unlocks, name: 'idx_covering_guild_deleted_at_player_achievement'
  end
end

class AddIndexesToAchievementUnlocks < ActiveRecord::Migration[8.0]
  def up
    add_index :achievement_unlocks, [ :achievement_id, :player_id, :id, :deleted_at ],
          name: 'idx_achievement_unlocks_covering_latest',
          order: { id: :desc }
  end

  def down
    remove_index :achievement_unlocks, name: 'idx_achievement_unlocks_covering_latest'
  end
end

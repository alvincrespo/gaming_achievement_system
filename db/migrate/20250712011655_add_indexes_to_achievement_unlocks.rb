class AddIndexesToAchievementUnlocks < ActiveRecord::Migration[8.0]
  def change
    # CRITICAL: This index is optimized for window function queries
    # The column order matches the query access pattern:
    # WHERE guild_id = ? AND deleted_at IS NULL
    # PARTITION BY player_id, achievement_id ORDER BY id DESC
    add_index :achievement_unlocks,
              [ :guild_id, :deleted_at, :player_id, :achievement_id, :id ],
              name: 'idx_window_function_optimal',
              order: { id: :desc }

    # This index helps the JOIN approach for GROUP BY operations
    # It allows efficient grouping by player_id, achievement_id after filtering
    add_index :achievement_unlocks,
              [ :guild_id, :deleted_at, :player_id, :achievement_id ],
              name: 'idx_join_approach'

    # This index optimizes for queries that filter by achievement_id
    # (like when you pre-filter eligible achievements)
    add_index :achievement_unlocks,
              [ :guild_id, :achievement_id, :deleted_at, :player_id, :id ],
              name: 'idx_achievement_filtered',
              order: { id: :desc }
  end

  def down
    remove_index :achievement_unlocks, name: 'idx_window_function_optimal'
    remove_index :achievement_unlocks, name: 'idx_join_approach'
    remove_index :achievement_unlocks, name: 'idx_achievement_filtered'
  end
end

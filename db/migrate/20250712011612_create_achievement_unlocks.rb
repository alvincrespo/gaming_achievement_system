class CreateAchievementUnlocks < ActiveRecord::Migration[8.0]
  def change
    create_table :achievement_unlocks do |t|
      t.references :player, null: false, foreign_key: true
      t.references :achievement, null: false, foreign_key: true
      t.references :guild, null: false, foreign_key: true
      t.datetime :unlocked_at
      t.integer :progress_percentage
      t.datetime :deleted_at

      t.timestamps
    end
  end
end

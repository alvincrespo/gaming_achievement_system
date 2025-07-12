class CreateGamesAchievements < ActiveRecord::Migration[8.0]
  def change
    create_table :games_achievements do |t|
      t.references :game, null: false, foreign_key: true
      t.references :achievement, null: false, foreign_key: true

      t.timestamps
    end
  end
end

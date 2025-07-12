class CreateGameships < ActiveRecord::Migration[8.0]
  def change
    create_table :gameships do |t|
      t.references :game, null: false, foreign_key: true
      t.references :achievement_category, null: false, foreign_key: true
      t.references :guild, null: false, foreign_key: true

      t.timestamps
    end
  end
end

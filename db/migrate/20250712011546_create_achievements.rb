class CreateAchievements < ActiveRecord::Migration[8.0]
  def change
    create_table :achievements do |t|
      t.string :name
      t.text :description
      t.integer :points
      t.integer :rarity
      t.string :icon_url

      t.timestamps
    end
  end
end

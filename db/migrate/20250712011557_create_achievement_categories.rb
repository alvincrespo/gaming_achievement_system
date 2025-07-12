class CreateAchievementCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :achievement_categories do |t|
      t.references :guild, null: false, foreign_key: true
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end

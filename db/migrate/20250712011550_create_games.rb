class CreateGames < ActiveRecord::Migration[8.0]
  def change
    create_table :games do |t|
      t.string :name
      t.text :description
      t.integer :genre
      t.string :platform

      t.timestamps
    end
  end
end

class CreatePlayers < ActiveRecord::Migration[8.0]
  def change
    create_table :players do |t|
      t.string :username
      t.string :email
      t.integer :level
      t.integer :total_points

      t.timestamps
    end
  end
end

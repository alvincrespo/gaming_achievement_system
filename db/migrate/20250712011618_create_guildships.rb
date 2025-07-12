class CreateGuildships < ActiveRecord::Migration[8.0]
  def change
    create_table :guildships do |t|
      t.references :guild, null: false, foreign_key: true
      t.integer :guild_type
      t.string :region

      t.timestamps
    end
  end
end

class Gameship < ApplicationRecord
  belongs_to :game
  belongs_to :achievement_category
  belongs_to :guild
  has_many :guildships, foreign_key: :guild_id, primary_key: :guild_id
end

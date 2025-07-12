class Gameship < ApplicationRecord
  belongs_to :game
  belongs_to :achievement_category
  belongs_to :guild
end

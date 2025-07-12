class GamesAchievement < ApplicationRecord
  belongs_to :game
  belongs_to :achievement
end

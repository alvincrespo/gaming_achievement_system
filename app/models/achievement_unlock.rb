class AchievementUnlock < ApplicationRecord
  belongs_to :player
  belongs_to :achievement
  belongs_to :guild
end

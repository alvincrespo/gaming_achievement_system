class AchievementCategory < ApplicationRecord
  belongs_to :guild
  has_many :gameships
  has_many :games, through: :gameships
end

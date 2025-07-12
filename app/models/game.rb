class Game < ApplicationRecord
  has_many :games_achievements
  has_many :achievements, through: :games_achievements
  has_many :gameships

  enum :genre, {
    action: 0,
    rpg: 1,
    strategy: 2,
    sports: 3,
    simulation: 4,
    puzzle: 5,
    mmo: 6
  }
end

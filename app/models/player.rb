class Player < ApplicationRecord
  has_many :achievement_unlocks
  has_many :achievements, through: :achievement_unlocks
  has_many :guilds, through: :achievement_unlocks

  def display_name
    "#{username}##{id.to_s.rjust(4, '0')}"
  end
end

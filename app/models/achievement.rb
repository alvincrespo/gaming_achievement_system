class Achievement < ApplicationRecord
  has_many :games_achievements
  has_many :games, through: :games_achievements
  has_many :achievement_unlocks

  enum rarity: {
    common: 0,
    uncommon: 1,
    rare: 2,
    epic: 3,
    legendary: 4
  }

  def self.eligible_for_guild(guild_id)
    joins(games: { gameships: :achievement_category })
      .where(achievement_categories: { guild_id: guild_id })
      .distinct
      .pluck(:id)
  end
end

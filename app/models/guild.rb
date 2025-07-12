class Guild < ApplicationRecord
  has_many :guildships
  has_many :achievement_categories
  has_many :gameships
  has_many :achievement_unlocks

  scope :with_unlock_count, -> {
    left_joins(:achievement_unlocks)
      .group(:id)
      .select("guilds.*, COUNT(achievement_unlocks.id) as unlock_count")
  }

  def guild_size_category
    count = achievement_unlocks.count
    case count
    when 0..100 then "Small"
    when 101..1000 then "Medium"
    when 1001..10000 then "Large"
    else "Mega"
    end
  end
end

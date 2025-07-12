class AchievementQueryStrategy
  attr_reader :guild_id

  def initialize(guild_id)
    @guild_id = guild_id
  end

  # Strategy 1: Using JOIN approach
  def latest_unlocks_with_joins
    AchievementUnlock
      .joins(achievement: { games_achievements: { game: { gameships: :guildships } } })
      .joins(
        <<-SQL
          INNER JOIN (
            SELECT MAX(au.id) as unlock_id
            FROM achievement_unlocks au
            INNER JOIN achievements ON achievements.id = au.achievement_id
            INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
            INNER JOIN games ON games.id = games_achievements.game_id
            INNER JOIN gameships ON gameships.game_id = games.id
            INNER JOIN guildships ON guildships.guild_id = gameships.guild_id
            WHERE au.deleted_at IS NULL
              AND guildships.guild_id = #{guild_id}
            GROUP BY au.player_id, au.achievement_id
          ) AS latest ON latest.unlock_id = achievement_unlocks.id
        SQL
      )
      .where("achievement_unlocks.deleted_at IS NULL")
      .where("guildships.guild_id = ?", guild_id)
  end

  # Strategy 2: Using Window Function with pre-filtering
  def latest_unlocks_with_window_function
    # Step 1: Get eligible achievement IDs
    eligible_achievement_ids = Achievement.eligible_for_guild(guild_id)

    return AchievementUnlock.none if eligible_achievement_ids.empty?

    # Step 2: Use window function to get latest unlocks
    sql = <<-SQL
      SELECT outer_unlocks.*
      FROM (
        SELECT inner_unlocks.*
        FROM (
          SELECT achievement_unlocks.*,
                 ROW_NUMBER() OVER (
                   PARTITION BY player_id, achievement_id
                   ORDER BY id DESC
                 ) AS rn
          FROM achievement_unlocks
          WHERE deleted_at IS NULL
            AND guild_id = ?
            AND achievement_id IN (?)
        ) inner_unlocks
        WHERE rn = 1
      ) AS outer_unlocks
      INNER JOIN achievements ON achievements.id = outer_unlocks.achievement_id
      INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
      INNER JOIN games ON games.id = games_achievements.game_id
      WHERE outer_unlocks.deleted_at IS NULL
    SQL

    AchievementUnlock.find_by_sql([sql, guild_id, eligible_achievement_ids])
  end

  # Benchmark method to compare both approaches
  def benchmark_approaches
    require 'benchmark'
    require 'timeout'

    results = {
      guild_id: guild_id,
      unlock_count: AchievementUnlock.where(guild_id: guild_id).count,
      eligible_achievements: Achievement.eligible_for_guild(guild_id).count
    }

    # Warm up
    latest_unlocks_with_window_function rescue nil
    latest_unlocks_with_joins rescue nil

    # Benchmark window function approach
    results[:window_function] = Benchmark.measure do
      results[:window_function_count] = latest_unlocks_with_window_function.size
    end.real

    # Benchmark join approach (with timeout protection)
    begin
      results[:join] = Benchmark.measure do
        Timeout::timeout(10) do
          results[:join_count] = latest_unlocks_with_joins.count
        end
      end.real
    rescue Timeout::Error
      results[:join] = 10.0
      results[:join_error] = "Query timed out after 10 seconds"
    end

    results[:speedup] = (results[:join] / results[:window_function]).round(2) if results[:join] > 0
    results
  end
end

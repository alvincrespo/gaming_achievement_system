class AchievementQueryStrategy
  attr_reader :guild_id

  def initialize(guild_id)
    @guild_id = guild_id
  end

  def base_latest_unlock_relation
    @base_latest_unlock_relation ||=
      AchievementUnlock.joins(achievement: { games_achievements: { game: { gameships: :guildships } } })
  end

  def latest_unlock_subquery
    AchievementUnlock
      .where(deleted_at: nil)
      .where(guild_id: guild_id)
      .group(:player_id, :achievement_id)
      .select("MAX(achievement_unlocks.id) as unlock_id")
  end

  # Strategy 1: Using JOIN approach
  def latest_unlocks_with_joins
    AchievementUnlock
      .joins(
        Arel.sql("INNER JOIN (#{latest_unlock_subquery.to_sql}) AS latest ON latest.unlock_id = achievement_unlocks.id")
      )
      .joins(achievement: { games_achievements: :game })
      .where("achievement_unlocks.deleted_at IS NULL")
      .where("achievement_unlocks.guild_id = ?", guild_id)
  end

  # Strategy 2: Using Window Function with pre-filtering
  def latest_unlocks_with_window_function
    # Step 1: Get eligible achievement IDs
    eligible_achievement_ids = Achievement.eligible_for_guild(guild_id)

    return AchievementUnlock.none if eligible_achievement_ids.empty?

    # Step 2: Use window function to get latest unlocks
    AchievementUnlock.find_by_sql([ window_function_sql, guild_id, eligible_achievement_ids ])
  end

  def window_function_sql
<<-SQL
  SELECT outer_unlocks.*
  FROM (
    SELECT inner_unlocks.*
    FROM (
      SELECT achievement_unlocks.*,
              ROW_NUMBER() OVER (PARTITION BY player_id, achievement_id ORDER BY id DESC) AS rn
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
  end

  # Benchmark method to compare both approaches
  def benchmark_approaches
    require "benchmark"
    require "timeout"

    # Get baseline data
    guild_id_value = guild_id

    # Benchmark window function approach
    window_function_count = 0
    window_function_time = Benchmark.measure do
      window_function_count = latest_unlocks_with_window_function.size
    end.real

    # Benchmark join approach (with timeout protection)
    join_count = 0
    join_time = Benchmark.measure do
      join_count = latest_unlocks_with_joins.count
    end.real

    # Create window function and join objects
    window_function_obj = {
      count: window_function_count,
      execution_time: window_function_time,
      type: "Window Function"
    }

    join_obj = {
      count: join_count,
      execution_time: join_time,
      type: "JOIN"
    }

    # Determine winner and loser
    if window_function_time < join_time
      winner = window_function_obj
      loser = join_obj
      speedup = (join_time / window_function_time).round(2)
    else
      winner = join_obj
      loser = window_function_obj
      speedup = (window_function_time / join_time).round(2)
    end

    {
      guild_id: guild_id_value,
      winner: winner,
      loser: loser,
      speedup: speedup
    }
  end
end

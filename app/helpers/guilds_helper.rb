module GuildsHelper
  def guild_size_class(unlock_count)
    case unlock_count
    when 0..100 then "badge-secondary"
    when 101..1000 then "badge-primary"
    when 1001..10000 then "badge-warning"
    else "badge-danger"
    end
  end

  def guild_size_label(unlock_count)
    case unlock_count
    when 0..100 then "Small"
    when 101..1000 then "Medium"
    when 1001..10000 then "Large"
    else "Mega"
    end
  end

  def join_query_example
    # Instead of trying to format the messy to_sql output,
    # let's create a clean example that shows the concept
    <<~SQL
      SELECT
        `achievement_unlocks`.*
      FROM
        `achievement_unlocks`
        INNER JOIN (
          SELECT
            MAX(achievement_unlocks.id) as unlock_id
          FROM
            `achievement_unlocks`
          WHERE
            `achievement_unlocks`.`deleted_at` IS NULL
            AND `achievement_unlocks`.`guild_id` = #{@guild.id}
          GROUP BY
            `achievement_unlocks`.`player_id`,
            `achievement_unlocks`.`achievement_id`
        ) AS latest ON latest.unlock_id = achievement_unlocks.id
        INNER JOIN `achievements` ON `achievements`.`id` = `achievement_unlocks`.`achievement_id`
        INNER JOIN `games_achievements` ON `games_achievements`.`achievement_id` = `achievements`.`id`
        INNER JOIN `games` ON `games`.`id` = `games_achievements`.`game_id`
      WHERE
        (achievement_unlocks.deleted_at IS NULL)
        AND (achievement_unlocks.guild_id = #{@guild.id})
    SQL
  end

  def window_function_example
    strategy = AchievementQueryStrategy.new(@guild.id)
    strategy.window_function_sql
  end
end

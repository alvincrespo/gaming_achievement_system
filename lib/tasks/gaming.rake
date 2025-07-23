require "ruby-progressbar"

namespace :gaming do
  desc "Benchmark queries"
  task benchmark: :environment do
    guild_id = ENV["guild_id"] || raise("Provide guild_id=")

    puts "Benchmarking massive dataset..."

    puts "\nBenchmarking Guild ID: #{guild_id}"
    # Window function
    puts "\nWindow Function:"
    eligible_achievement_ids = ActiveRecord::Base.connection.execute(<<-SQL
      SELECT DISTINCT achievements.id
      FROM achievements
      INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
      INNER JOIN games ON games.id = games_achievements.game_id
      INNER JOIN gameships ON gameships.game_id = games.id
      INNER JOIN achievement_categories ON achievement_categories.id = gameships.achievement_category_id
      WHERE achievement_categories.guild_id = #{guild_id}
    SQL
    ).to_a.join(",")
    start = Time.current
    count = ActiveRecord::Base.connection.execute(<<-SQL
      SELECT outer_unlocks.*
      FROM (
        SELECT inner_unlocks.*
        FROM (
          SELECT achievement_unlocks.*,
                  ROW_NUMBER() OVER (PARTITION BY player_id, achievement_id ORDER BY id DESC) AS rn
          FROM achievement_unlocks
          WHERE deleted_at IS NULL
            AND guild_id = #{guild_id}
            AND achievement_id IN (#{eligible_achievement_ids})
        ) inner_unlocks
        WHERE rn = 1
      ) AS outer_unlocks
      INNER JOIN achievements ON achievements.id = outer_unlocks.achievement_id
      INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
      INNER JOIN games ON games.id = games_achievements.game_id
      WHERE outer_unlocks.deleted_at IS NULL
    SQL
    ).first[0]
    window_time = Time.current - start
    puts "  Time: #{window_time.round(3)}s"
    puts "  Rows: #{count}"

    # JOIN
    puts "\nJOIN Approach:"
    start = Time.current
    count = ActiveRecord::Base.connection.execute(<<-SQL
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
            AND `achievement_unlocks`.`guild_id` = #{guild_id}
          GROUP BY
            `achievement_unlocks`.`player_id`,
            `achievement_unlocks`.`achievement_id`
        ) AS latest ON latest.unlock_id = achievement_unlocks.id
        INNER JOIN `achievements` ON `achievements`.`id` = `achievement_unlocks`.`achievement_id`
        INNER JOIN `games_achievements` ON `games_achievements`.`achievement_id` = `achievements`.`id`
        INNER JOIN `games` ON `games`.`id` = `games_achievements`.`game_id`
      WHERE
        (achievement_unlocks.deleted_at IS NULL)
        AND (achievement_unlocks.guild_id = #{guild_id})
    SQL
    ).first[0]
    join_time = Time.current - start
    puts "  Time: #{join_time.round(3)}s"
    puts "  Rows: #{count}"

    if window_time < join_time
      puts "\n✅ Window function is #{(join_time / window_time).round(2)}x faster!"
    else
      puts "\n❌ JOIN is still faster. Your MySQL version/config is highly optimized for GROUP BY."
    end
  end
end

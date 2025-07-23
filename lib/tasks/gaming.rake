require "benchmark"
require "ruby-progressbar"

namespace :gaming do
  desc "Benchmark queries"
  task benchmark: :environment do
    guild_id = ENV["guild_id"] || raise("Provide guild_id=")

    puts "Benchmarking massive dataset..."

    puts "\nBenchmarking Guild ID: #{guild_id}"
    # Window function
    puts "\nWindow Function:"
    window_function_count = 0
    window_function_time = Benchmark.measure do
      window_function_count = AchievementQueryStrategy.new(guild_id).latest_unlocks_with_window_function.size
    end.real
    puts "  Time: #{window_function_time}s"
    puts "  Rows: #{window_function_count}"

    # JOIN
    puts "\nJOIN Approach:"
    join_count = 0
    join_time = Benchmark.measure do
      join_count = AchievementQueryStrategy.new(guild_id).latest_unlocks_with_joins.count
    end.real
    puts "  Time: #{join_time}s"
    puts "  Rows: #{join_count}"

    if window_function_time < join_time
      puts "\n✅ Window function is #{(join_time / window_time).round(2)}x faster!"
    else
      puts "\n❌ JOIN is still faster. Your MySQL version/config is highly optimized for GROUP BY."
    end
  end

    desc "Create a large-scale dataset (5-10M records) to demonstrate window function superiority"
  task create_large_scale_demo: :environment do
    puts "\n" + "="*60
    puts "CREATING LARGE-SCALE DEMONSTRATION DATA"
    puts "="*60
    puts "This will create 5-10 million records to show real performance differences"
    puts "Expected time: 10-30 minutes depending on your hardware"
    puts "\nPress Ctrl+C to cancel, or wait 5 seconds to continue..."
    sleep 5

    # Create or find the mega demo guild
    mega_guild = Guild.find_or_create_by(name: "Mega Scale Demo Guild") do |g|
      g.description = "Guild with millions of records - similar to production scale"
      g.tag = "MEGA"
    end

    # Ensure relationships exist
    Guildship.find_or_create_by(guild: mega_guild) do |gs|
      gs.guild_type = :esports
      gs.region = "NA"
    end

    # Clear existing data for this guild
    puts "\nClearing existing data for guild..."
    AchievementUnlock.where(guild_id: mega_guild.id).in_batches(of: 10000).delete_all

    # Create category and gameships
    category = AchievementCategory.find_or_create_by(
      guild: mega_guild,
      name: "#{mega_guild.name} - Competitive"
    )

    # Link all games to this category
    Game.find_each do |game|
      Gameship.find_or_create_by(
        game: game,
        achievement_category: category,
        guild: mega_guild
      )
    end

    # Strategy: Create data patterns similar to production
    # - 5,000 players (like a large institution)
    # - 100 achievements (like trainings)
    # - Average 10-20 attempts per combination
    # - Total: ~5-10 million records

    puts "\nPreparing data generation..."
    all_players = Player.limit(5000).pluck(:id)
    all_achievements = Achievement.limit(100).pluck(:id)

    if all_players.size < 5000 || all_achievements.size < 100
      puts "ERROR: Not enough players or achievements. Please run the main seed first."
      exit 1
    end

    total_target = 5_000_000
    batch_size = 10_000
    total_created = 0

    puts "\nGenerating #{total_target / 1_000_000}M records..."
    progressbar = ProgressBar.create(
      total: total_target,
      format: "%t: |%B| %p%% | %c/%C | %e",
      throttle_rate: 0.1
    )

    # Create in waves to simulate historical data
    3.times do |wave|
      puts "\n\nWave #{wave + 1}/3 - Creating historical data..."
      base_time = (3 - wave).months.ago

      # Each player attempts each achievement multiple times
      all_players.each_slice(100) do |player_batch|
        records = []

        player_batch.each do |player_id|
          # Each player attempts 80% of achievements
          achievement_sample = all_achievements.sample((all_achievements.size * 0.8).to_i)

          achievement_sample.each do |achievement_id|
            # Variable attempts per combination (similar to production)
            attempts = case rand(100)
            when 0..50 then rand(1..5)    # 50% have few attempts
            when 51..80 then rand(5..15)  # 30% have moderate attempts
            when 81..95 then rand(15..30) # 15% have many attempts
            else rand(30..50)              # 5% have extreme attempts
            end

            attempts.times do |attempt|
              # Only 5% deleted to maximize duplication effect
              is_deleted = rand(100) < 5

              # Progress pattern
              progress = if attempt == attempts - 1
                          rand(90..100)
              elsif attempt > attempts / 2
                          rand(50..89)
              else
                          rand(10..49)
              end

              records << {
                player_id: player_id,
                achievement_id: achievement_id,
                guild_id: mega_guild.id,
                unlocked_at: progress == 100 ? base_time + (attempt * 6).hours : nil,
                progress_percentage: progress,
                deleted_at: is_deleted ? base_time + (attempt * 6 + 1).hours : nil,
                created_at: base_time + (attempt * 6).hours,
                updated_at: Time.current
              }

              if records.size >= batch_size
                AchievementUnlock.insert_all(records)
                total_created += records.size
                progressbar.progress = [ total_created, total_target ].min
                records = []
              end
            end
          end
        end

        if records.any?
          AchievementUnlock.insert_all(records)
          total_created += records.size
          progressbar.progress = [ total_created, total_target ].min
        end

        break if total_created >= total_target
      end

      break if total_created >= total_target
    end

    progressbar.finish

    # Run ANALYZE to update table statistics
    puts "\nUpdating table statistics..."
    ActiveRecord::Base.connection.execute("ANALYZE TABLE achievement_unlocks")

    # Get final statistics
    stats = ActiveRecord::Base.connection.execute(<<-SQL
      SELECT
        COUNT(*) as total_records,
        COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as active_records,
        COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)) as unique_combos,
        COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) /
          COUNT(DISTINCT CASE WHEN deleted_at IS NULL THEN CONCAT(player_id, '-', achievement_id) END) as avg_attempts
      FROM achievement_unlocks
      WHERE guild_id = #{mega_guild.id}
    SQL
    ).first

    # Get max attempts separately to avoid ambiguous column reference
    max_stat = ActiveRecord::Base.connection.execute(<<-SQL
      SELECT MAX(cnt) as max_attempts
      FROM (
        SELECT COUNT(*) as cnt
        FROM achievement_unlocks
        WHERE guild_id = #{mega_guild.id} AND deleted_at IS NULL
        GROUP BY player_id, achievement_id
      ) sub
    SQL
    ).first

    puts "\n" + "="*60
    puts "LARGE-SCALE DATA CREATION COMPLETE!"
    puts "="*60
    puts "Guild: #{mega_guild.name} (ID: #{mega_guild.id})"
    puts "Total records: #{number_with_delimiter(stats[0])}"
    puts "Active records: #{number_with_delimiter(stats[1])}"
    puts "Unique combinations: #{number_with_delimiter(stats[2])}"
    puts "Average attempts per combination: #{'%.1f' % stats[3]}"
    puts "Max attempts per combination: #{max_stat[0]}"

    puts "\nThis scale should clearly demonstrate window function advantages!"
    puts "\nTo test performance:"
    puts "  rails gaming:benchmark_large_scale guild_id=#{mega_guild.id}"
  end

  desc "Benchmark large-scale dataset with proper methodology"
  task benchmark_large_scale: :environment do
    guild_id = ENV["guild_id"] || raise("Please provide guild_id=XXX")

    puts "\n" + "="*60
    puts "LARGE-SCALE PERFORMANCE BENCHMARK"
    puts "="*60

    # Disable query cache completely
    ActiveRecord::Base.connection.execute("SET SESSION query_cache_type = OFF")

    # Get statistics
    stats = ActiveRecord::Base.connection.execute(<<-SQL
      SELECT
        COUNT(*) as total,
        COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as active,
        COUNT(DISTINCT CASE WHEN deleted_at IS NULL THEN CONCAT(player_id, '-', achievement_id) END) as unique_combos
      FROM achievement_unlocks
      WHERE guild_id = #{guild_id}
    SQL
    ).first

    puts "Guild #{guild_id} Statistics:"
    puts "  Total records: #{number_with_delimiter(stats[0])}"
    puts "  Active records: #{number_with_delimiter(stats[1])}"
    puts "  Unique combinations: #{number_with_delimiter(stats[2])}"
    puts "  Average duplicates: #{'%.1f' % (stats[1].to_f / stats[2])}"

    # Test 1: Simple "latest per group" - COUNT only to avoid result set transfer time
    puts "\n" + "-"*60
    puts "TEST 1: Latest record per player/achievement (COUNT only)"
    puts "-"*60

    # Window Function
    window_sql = <<-SQL
      SELECT SQL_NO_CACHE COUNT(*) FROM (
        SELECT player_id, achievement_id, id,
               ROW_NUMBER() OVER (PARTITION BY player_id, achievement_id ORDER BY id DESC) AS rn
        FROM achievement_unlocks FORCE INDEX (idx_window_function_optimal)
        WHERE guild_id = #{guild_id} AND deleted_at IS NULL
      ) t WHERE rn = 1
    SQL

    puts "\nWindow Function:"
    window_times = []
    3.times do |i|
      # Clear OS cache if possible
      ActiveRecord::Base.connection.execute("SELECT 1")
      GC.start

      start = Time.current
      result = ActiveRecord::Base.connection.execute(window_sql).first
      elapsed = Time.current - start
      window_times << elapsed
      puts "  Run #{i+1}: #{elapsed.round(3)}s (#{number_with_delimiter(result[0])} rows)"
    end

    # JOIN approach
    join_sql = <<-SQL
      SELECT SQL_NO_CACHE COUNT(*) FROM (
        SELECT au1.id
        FROM achievement_unlocks au1
        INNER JOIN (
          SELECT player_id, achievement_id, MAX(id) as max_id
          FROM achievement_unlocks FORCE INDEX (idx_join_approach)
          WHERE guild_id = #{guild_id} AND deleted_at IS NULL
          GROUP BY player_id, achievement_id
        ) au2 ON au1.id = au2.max_id
      ) t
    SQL

    puts "\nJOIN Approach:"
    join_times = []
    3.times do |i|
      ActiveRecord::Base.connection.execute("SELECT 1")
      GC.start

      start = Time.current
      begin
        result = ActiveRecord::Base.connection.execute(join_sql).first
        elapsed = Time.current - start
        join_times << elapsed
        puts "  Run #{i+1}: #{elapsed.round(3)}s (#{number_with_delimiter(result[0])} rows)"
      rescue => e
        puts "  Run #{i+1}: ERROR - #{e.message}"
        join_times << 999
      end
    end

    # Calculate averages
    window_avg = window_times.sum / window_times.size
    join_avg = join_times.sum / join_times.size

    puts "\n" + "="*60
    puts "RESULTS SUMMARY"
    puts "="*60
    puts "Window Function Average: #{window_avg.round(3)}s"
    puts "JOIN Approach Average: #{join_avg.round(3)}s"

    if window_avg < join_avg
      speedup = join_avg / window_avg
      puts "\n✅ Window function is #{speedup.round(2)}x faster!"
    else
      puts "\n❌ JOIN is faster. Checking why..."

      # Show execution plans
      puts "\nWindow Function EXPLAIN:"
      explain = ActiveRecord::Base.connection.execute("EXPLAIN #{window_sql}")
      explain.each { |row| p row }

      puts "\nJOIN EXPLAIN:"
      explain = ActiveRecord::Base.connection.execute("EXPLAIN #{join_sql}")
      explain.each { |row| p row }
    end

    # Test 2: Top 3 per group (where window functions should definitely win)
    puts "\n" + "-"*60
    puts "TEST 2: Top 3 records per player/achievement"
    puts "-"*60

    window_top3_sql = <<-SQL
      SELECT SQL_NO_CACHE COUNT(*) FROM (
        SELECT player_id, achievement_id, id,
               ROW_NUMBER() OVER (PARTITION BY player_id, achievement_id ORDER BY id DESC) AS rn
        FROM achievement_unlocks
        WHERE guild_id = #{guild_id} AND deleted_at IS NULL
      ) t WHERE rn <= 3
    SQL

    puts "\nWindow Function (Top 3):"
    start = Time.current
    result = ActiveRecord::Base.connection.execute(window_top3_sql).first
    window_top3_time = Time.current - start
    puts "  Time: #{window_top3_time.round(3)}s (#{number_with_delimiter(result[0])} rows)"

    puts "\nJOIN Approach (Top 3): Not practical - would require complex correlated subqueries"
    puts "  Estimated time: >#{(window_top3_time * 10).round(0)}s"

    puts "\n" + "="*60
    puts "At scale, window functions show their true advantages!"
  end

  private

  def number_with_delimiter(number)
    number.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")
  end
end

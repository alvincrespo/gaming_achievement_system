require 'faker'
require 'ruby-progressbar'

class GamingSeedGenerator
  attr_reader :stats

  def initialize
    @stats = {}
    puts "Starting Gaming Achievement Database Seed..."
    puts "This will create realistic data distributions to demonstrate query performance differences."
  end

  def generate!
    ActiveRecord::Base.transaction do
      create_guilds
      create_players
      create_games
      create_achievements
      create_achievement_categories
      create_games_achievements
      create_achievement_unlocks
      print_statistics
    end
  end

  private

  def create_guilds
    puts "\n1. Creating Guilds..."
    progressbar = ProgressBar.create(total: 1000, format: '%t: |%B| %p%% %e')

    guilds = []

    # 90% small guilds (900)
    900.times do |i|
      guilds << {
        name: "#{Faker::Games::DnD.city} #{[ 'Raiders', 'Knights', 'Dragons', 'Phoenix', 'Legends' ].sample}",
        description: Faker::Games::WorldOfWarcraft.quote,
        tag: generate_guild_tag,
        created_at: Time.current,
        updated_at: Time.current
      }
      progressbar.increment
    end

    # 9% medium guilds (90)
    90.times do |i|
      guilds << {
        name: "#{Faker::Games::LeagueOfLegends.champion} #{[ 'Elite', 'Pro', 'Masters' ].sample}",
        description: "Competitive guild focused on high-level play",
        tag: generate_guild_tag,
        created_at: Time.current,
        updated_at: Time.current
      }
      progressbar.increment
    end

    # 1% mega guilds (10)
    mega_guild_names = [
      "FaZe Clan", "Team SoloMid", "Cloud9", "G2 Esports", "Fnatic",
      "100 Thieves", "OpTic Gaming", "Team Liquid", "NRG Esports", "Sentinels"
    ]

    mega_guild_names.each do |name|
      guilds << {
        name: name,
        description: "Professional esports organization",
        tag: name.split.map(&:first).join.upcase[0..4],
        created_at: Time.current,
        updated_at: Time.current
      }
      progressbar.increment
    end

    Guild.insert_all(guilds)

    # Create guildships
    Guild.find_each do |guild|
      guild_type = case guild.name
      when /FaZe|TSM|Cloud9|G2|Fnatic|100|OpTic|Liquid|NRG|Sentinels/
                     :esports
      when /Elite|Pro|Masters/
                     :competitive
      else
                     [ :casual, :social, :streaming ].sample
      end

      Guildship.create!(
        guild: guild,
        guild_type: guild_type,
        region: [ 'NA', 'EU', 'ASIA' ].sample
      )
    end

    @stats[:guilds] = Guild.count
  end

  def create_players
    puts "\n2. Creating Players..."
    progressbar = ProgressBar.create(total: 50_000, format: '%t: |%B| %p%% %e')

    players = []
    50_000.times do
      players << {
        username: generate_gamer_username,
        email: Faker::Internet.unique.email,
        level: rand(1..100),
        total_points: rand(0..50000),
        created_at: Time.current,
        updated_at: Time.current
      }

      if players.size >= 1000
        Player.insert_all(players)
        progressbar.progress += players.size
        players = []
      end
    end

    Player.insert_all(players) if players.any?
    @stats[:players] = Player.count
  end

  def create_games
    puts "\n3. Creating Games..."

    game_data = [
      { name: "Call of Duty: Warzone", genre: :action },
      { name: "League of Legends", genre: :mmo },
      { name: "Fortnite", genre: :action },
      { name: "Valorant", genre: :action },
      { name: "World of Warcraft", genre: :mmo }
    ]

    total_games = game_data.size * 10
    progressbar = ProgressBar.create(total: total_games, format: '%t: |%B| %p%% %e')

    games = []
    game_data.each do |data|
      10.times do |i|
        season = i == 0 ? "" : " Season #{i}"
        games << {
          name: "#{data[:name]}#{season}",
          description: Faker::Lorem.paragraph,
          genre: Game.genres[data[:genre]],
          platform: "Multi-platform",
          created_at: Time.current,
          updated_at: Time.current
        }
        progressbar.increment
      end
    end

    Game.insert_all(games)
    @stats[:games] = Game.count
  end

  def create_achievements
    puts "\n4. Creating Achievements..."

    achievement_types = [
      { prefix: "First", rarity: :common, points: 10 },
      { prefix: "Master", rarity: :uncommon, points: 25 },
      { prefix: "Elite", rarity: :rare, points: 50 },
      { prefix: "Legendary", rarity: :epic, points: 100 }
    ]

    total_achievements = achievement_types.size * 25
    progressbar = ProgressBar.create(total: total_achievements, format: '%t: |%B| %p%% %e')

    achievements = []
    achievement_types.each do |type|
      25.times do |i|
        achievements << {
          name: "#{type[:prefix]} Achievement #{i+1}",
          description: Faker::Lorem.sentence,
          points: type[:points],
          rarity: Achievement.rarities[type[:rarity]],
          created_at: Time.current,
          updated_at: Time.current
        }
        progressbar.increment
      end
    end

    Achievement.insert_all(achievements)
    @stats[:achievements] = Achievement.count
  end

  def create_achievement_categories
    puts "\n5. Creating Achievement Categories..."

    progressbar = ProgressBar.create(total: Guild.count, format: '%t: |%B| %p%% %e')

    Guild.find_each do |guild|
      rand(2..5).times do
        category = AchievementCategory.create!(
          guild: guild,
          name: "#{guild.name} - #{[ 'PvP', 'PvE', 'Social' ].sample}",
          description: Faker::Lorem.sentence
        )

        # Link games
        Game.all.sample(rand(3..10)).each do |game|
          Gameship.create!(
            game: game,
            achievement_category: category,
            guild: guild
          )
        end
      end
      progressbar.increment
    end
  end

  def create_games_achievements
    puts "\n6. Creating Games-Achievements Links..."

    progressbar = ProgressBar.create(total: Game.count, format: '%t: |%B| %p%% %e')

    Game.find_each do |game|
      Achievement.all.sample(rand(20..50)).each do |achievement|
        GamesAchievement.create!(
          game: game,
          achievement: achievement
        )
      end
      progressbar.increment
    end

    @stats[:games_achievements] = GamesAchievement.count
  end

  def create_achievement_unlocks
    puts "\n7. Creating Achievement Unlocks..."

    small_guilds = Guild.limit(900)
    medium_guilds = Guild.offset(900).limit(90)
    mega_guilds = Guild.offset(990).limit(10)

    progressbar = ProgressBar.create(total: 1000, format: '%t: |%B| %p%% %e')

    # Small guilds: 50-500 unlocks
    create_unlocks_for_guilds(small_guilds, 50..500, progressbar)

    # Medium guilds: 500-5000 unlocks
    create_unlocks_for_guilds(medium_guilds, 500..5000, progressbar)

    # Mega guilds: 5000-60000 unlocks
    create_unlocks_for_guilds(mega_guilds, 5000..60000, progressbar)

    @stats[:achievement_unlocks] = AchievementUnlock.count
  end

  def create_unlocks_for_guilds(guilds, count_range, progressbar)
    guilds.each do |guild|
      count = rand(count_range)

      eligible_achievement_ids = Achievement.eligible_for_guild(guild.id)
      next if eligible_achievement_ids.empty?

      player_count = case guild.name
      when /FaZe|TSM|Cloud9/ then rand(1000..5000)
      when /Elite|Pro|Masters/ then rand(100..500)
      else rand(10..100)
      end

      guild_players = Player.all.sample(player_count)

      count.times.each_slice(1000) do |batch|
        unlocks = batch.map do
          player = guild_players.sample
          achievement_id = eligible_achievement_ids.sample

          is_deleted = [ true, false ].sample
          progress = rand(0..100)
          unlock_time = rand(2.years.ago..Time.current)

          {
            player_id: player.id,
            achievement_id: achievement_id,
            guild_id: guild.id,
            unlocked_at: progress == 100 ? unlock_time : nil,
            progress_percentage: progress,
            deleted_at: is_deleted ? rand(unlock_time..Time.current) : nil,
            created_at: unlock_time,
            updated_at: Time.current
          }
        end
        AchievementUnlock.insert_all(unlocks)
      end
      progressbar.increment
    end
  end

  def generate_guild_tag
    (0...rand(3..5)).map { ('A'..'Z').to_a.sample }.join
  end

  def generate_gamer_username
    prefixes = [ 'Dark', 'Shadow', 'Ghost', 'Ninja', 'Pro', 'Elite' ]
    names = [ 'Wolf', 'Dragon', 'Phoenix', 'Warrior', 'Sniper', 'Knight' ]
    suffixes = [ '', '420', '69', '007', 'YT', rand(0..999).to_s ]

    "#{prefixes.sample}#{names.sample}#{suffixes.sample}"
  end

  def print_statistics
    puts "\n\nSeed Complete! Gaming Database Statistics:"
    puts "=" * 50
    puts "Guilds: #{@stats[:guilds]}"
    puts "Players: #{@stats[:players]}"
    puts "Games: #{@stats[:games]}"
    puts "Achievements: #{@stats[:achievements]}"
    puts "Game-Achievement Relations: #{@stats[:games_achievements]}"
    puts "Achievement Unlocks: #{@stats[:achievement_unlocks]}"
    puts "\nTop 10 Guilds by Unlock Count:"

    Guild.joins(:achievement_unlocks)
         .group(:id)
         .order('COUNT(achievement_unlocks.id) DESC')
         .limit(10)
         .pluck(:name, 'COUNT(achievement_unlocks.id)')
         .each do |name, count|
      puts "  #{name}: #{count} unlocks"
    end
  end
end

# Clear existing data
puts "Clearing existing data..."
ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 0")
ActiveRecord::Base.connection.tables.each do |table|
  next if [ "schema_migrations", "ar_internal_metadata" ].include?(table)
  ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{table}")
end
ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 1")

# Run the seed generator
GamingSeedGenerator.new.generate!

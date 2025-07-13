class GuildsController < ApplicationController
  def index
    @guilds = Guild.with_unlock_count
                   .order("unlock_count DESC")
                   .limit(20)
  end

  def show
    @guild = Guild.find(params[:id])
    @recent_unlocks = @guild.achievement_unlocks
                            .active
                            .includes(:player, :achievement)
                            .order(unlocked_at: :desc)
                            .limit(10)
    @top_players = Player.joins(:achievement_unlocks)
                         .where(achievement_unlocks: { guild_id: @guild.id })
                         .group("players.id")
                         .order("COUNT(achievement_unlocks.id) DESC")
                         .limit(10)
                         .select("players.*, COUNT(achievement_unlocks.id) as total_achievements")
  end

  def achievements
    @guild = Guild.find(params[:id])
    strategy = AchievementQueryStrategy.new(@guild.id)

    @unlocks = strategy.latest_unlocks_with_window_function
    @unlocks_by_player = @unlocks.group_by(&:player_id)
  end

  def compare_queries
    @guild = Guild.find(params[:id])
    @strategy = AchievementQueryStrategy.new(@guild.id)
  end

  def benchmark
    @guild = Guild.find(params[:id])
    strategy = AchievementQueryStrategy.new(@guild.id)

    results = strategy.benchmark_approaches

    render json: results
  end
end

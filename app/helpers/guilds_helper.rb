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
    strategy = AchievementQueryStrategy.new(@guild.id)

    # Get the actual JOIN query SQL
    join_relation = strategy.latest_unlocks_with_joins
    join_relation.to_sql
  end

  def window_function_example
    strategy = AchievementQueryStrategy.new(@guild.id)
    strategy.window_function_sql
  end
end

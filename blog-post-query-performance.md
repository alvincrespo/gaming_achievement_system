# A Deep Dive into MySQL Query Optimization at Scale

Recently, I've had to work with some large datasets across multiple tables. I work on an enterprise-level application that's 15+ years old at this point, so performance challenges at scale are not uncommon. But this particular problem pushed us to fundamentally rethink our approach to a seemingly simple query pattern.

The requirement was straightforward: retrieve the most recent record for each user-entity combination within a specific group. Think of it as "get the latest status update for each user's interaction with various resources." With 33 million records in our main table and some organizations having over 60,000 records, what started as a routine query optimization task became a deep dive into MySQL's execution strategies.

Initial performance metrics were alarming:
- Page wouldn't load for large, complex customers (losing trust)
- After basic optimizations, the query would timeout 30 seconds (unreliable implementations)
- Database CPU spiking to 100% (expensive resources)
- Connection pool exhaustion during peak hours

This article explores how I went about solving this using a combination of efficient indexes, explaining why window functions could help over the traditional JOIN for scale, and — surprisingly — when JOINs can still outperform window functions.

## Understanding the data model

To demonstrate these concepts, I built a complete gaming achievement system that mirrors our production data patterns. You can explore the full implementation at [github.com/alvincrespo/gaming_achievement_system](https://github.com/alvincrespo/gaming_achievement_system).

The simplified model consists of:

```ruby
class Player < ApplicationRecord           # Users
  has_many :achievement_unlocks
end

class Achievement < ApplicationRecord      # Entities/Resources
  has_many :achievement_unlocks
end

class Guild < ApplicationRecord            # Groups
  has_many :achievement_unlocks
end

class AchievementUnlock < ApplicationRecord  # User-Entity interactions
  belongs_to :player
  belongs_to :achievement
  belongs_to :guild
  # Multiple attempts tracked (progress_percentage, unlocked_at, deleted_at)
end
```

The critical characteristic: users make multiple attempts at achievements, creating 10-50 records per user-achievement combination. We need the most recent attempt for each combination.

## Base queries to be benchmarked

To retrieve the most recent attempt for each combination, there are two approaches we can take:

**Traditional Joins**

```sql
SELECT
  achievement_unlocks.*
FROM
  achievement_unlocks
  INNER JOIN (
    SELECT
      MAX(achievement_unlocks.id) as unlock_id
    FROM
      achievement_unlocks
    WHERE
      achievement_unlocks.deleted_at IS NULL
      AND achievement_unlocks.guild_id = (?)
    GROUP BY
      achievement_unlocks.player_id,
      achievement_unlocks.achievement_id
  ) AS latest ON latest.unlock_id = achievement_unlocks.id
  INNER JOIN achievements ON achievements.id = achievement_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  (achievement_unlocks.deleted_at IS NULL)
  AND (achievement_unlocks.guild_id = (?))
```

How it works:

- The subquery finds the maximum (latest) id for each unique pair of player_id and achievement_id in the achievement_unlocks table, filtered by a specific guild_id and only including records that are not deleted (deleted_at IS NULL).
- The main query then joins this result back to the achievement_unlocks table to get the full details of each latest unlock.
- Additional joins bring in related data from the achievements, games_achievements, and games tables.
- The final result is filtered again to ensure only active (not deleted) unlocks for the specified guild are returned.

In summary: it returns the latest achievement unlock for every player-achievement pair in a guild, along with related achievement and game info, ignoring deleted records.

**Window Functions**

```sql
SELECT outer_unlocks.*
FROM (
  SELECT inner_unlocks.*
  FROM (
    SELECT achievement_unlocks.*,
            ROW_NUMBER() OVER (PARTITION BY player_id, achievement_id ORDER BY id DESC) AS rn
    FROM achievement_unlocks
    WHERE deleted_at IS NULL
      AND guild_id = (?)
      AND achievement_id IN (?)
  ) inner_unlocks
  WHERE rn = 1
) AS outer_unlocks
INNER JOIN achievements ON achievements.id = outer_unlocks.achievement_id
INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  outer_unlocks.deleted_at IS NULL
```

How it works:

- The innermost subquery selects all achievement unlocks for a given guild and a set of achievement IDs, where the record is not deleted.
- It adds a row number (rn) to each record, partitioned by player_id and achievement_id, ordered by id descending. This means the latest unlock for each player-achievement pair gets rn = 1.
- The next subquery filters to only those records where rn = 1, so only the latest unlock per combination is kept.
- The outer query joins these latest unlocks to related tables (achievements, games_achievements, and games) to enrich the result.
- The final result only includes unlocks that are not deleted.

In summary: it returns the latest achievement unlock for every player-achievement pair, along with related achievement and game info, ignoring deleted records. The window function makes this efficient for large, highly duplicated datasets.

Each approach has it's tradeoffs as you'll discover later on. We do get a hint here that the window function may be extremely useful in larger datasets with higher duplication rates (ie. achievement unlocking attempts). However, regardless of the query, it's important to keep in mind that indexes are extremely useful and should be implemented in correlation with the development of your queries. One or the other, perhaps both, may benefit equally with highly targeted indexes.

To determine which is more useful, we need to take a step back and understand our data. We can take the approach of using trial and error tests, but I highly recommend attempting to understand what your data looks like in situations like these where determining approach can significantly impact performance and effectiveness of data retrieval.

## Statistics of our Demo

Before we move on, let's examine some high level stats of our demo application.

**Guilds with high unlocked achievements**

```sql
SELECT g.id, g.name, COUNT(au.id) as record_count
FROM guilds g
  LEFT JOIN achievement_unlocks au ON au.guild_id = g.id
GROUP BY g.id, g.name
HAVING record_count > 100000
ORDER BY record_count DESC;

+------+----------------------------+--------------+
| id   | name                       | record_count |
+------+----------------------------+--------------+
| 1002 | Mega Scale Demo Guild      |      5011697 |
| 1001 | Window Function Demo Guild |       298545 |
+------+----------------------------+--------------+
```

**Table Size Overview**

```sql
SELECT
    'players' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT id) as unique_records,
    MIN(created_at) as earliest_record,
    MAX(created_at) as latest_record
FROM players
UNION ALL
SELECT
    'achievement_unlocks' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT id) as unique_records,
    MIN(created_at) as earliest_record,
    MAX(created_at) as latest_record
FROM achievement_unlocks
UNION ALL
SELECT
    'achievements' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT id) as unique_records,
    MIN(created_at) as earliest_record,
    MAX(created_at) as latest_record
FROM achievements
UNION ALL
SELECT
    'guilds' as table_name,
    COUNT(*) as total_records,
    COUNT(DISTINCT id) as unique_records,
    MIN(created_at) as earliest_record,
    MAX(created_at) as latest_record
FROM guilds;

+---------------------+---------------+----------------+----------------------------+----------------------------+
| table_name          | total_records | unique_records | earliest_record            | latest_record              |
+---------------------+---------------+----------------+----------------------------+----------------------------+
| players             |         50000 |          50000 | 2025-07-23 14:24:14.885860 | 2025-07-23 14:24:21.943389 |
| achievement_unlocks |       6061665 |        6061665 | 2024-07-23 15:04:56.208071 | 2025-08-04 11:20:57.905334 |
| achievements        |           100 |            100 | 2025-07-23 14:24:22.046921 | 2025-07-23 14:24:22.051769 |
| guilds              |          1002 |           1002 | 2025-07-23 14:24:13.707298 | 2025-07-23 14:30:58.746264 |
+---------------------+---------------+----------------+----------------------------+----------------------------+
```

**Active Unlocked Achievements**

```sql
SELECT
    COUNT(*) as total_unlocks,
    COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as active_unlocks,
    COUNT(CASE WHEN deleted_at IS NOT NULL THEN 1 END) as deleted_unlocks,
    ROUND(COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) * 100.0 / COUNT(*), 2) as active_percentage
FROM achievement_unlocks;

+---------------+----------------+-----------------+-------------------+
| total_unlocks | active_unlocks | deleted_unlocks | active_percentage |
+---------------+----------------+-----------------+-------------------+
|       6061665 |        5720948 |          340717 |             94.38 |
+---------------+----------------+-----------------+-------------------+
```

**Guild Size Distribution**

```sql
SELECT
    guild_id,
    COUNT(*) as total_unlocks,
    COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as active_unlocks,
    COUNT(DISTINCT player_id) as unique_players,
    COUNT(DISTINCT achievement_id) as unique_achievements,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT player_id), 2) as avg_unlocks_per_player,
    ROUND(COUNT(*) * 1.0 / COUNT(DISTINCT achievement_id), 2) as avg_unlocks_per_achievement
FROM achievement_unlocks
GROUP BY guild_id
ORDER BY total_unlocks DESC;

+----------+---------------+----------------+----------------+---------------------+------------------------+-----------------------------+
| guild_id | total_unlocks | active_unlocks | unique_players | unique_achievements | avg_unlocks_per_player | avg_unlocks_per_achievement |
+----------+---------------+----------------+----------------+---------------------+------------------------+-----------------------------+
|     1002 |       5011697 |        4761284 |           5000 |                 100 |                1002.34 |                    50116.97 |
|     1001 |        298545 |         283668 |            200 |                  50 |                1492.73 |                     5970.90 |
|      995 |         54875 |          49422 |             19 |                 100 |                2888.16 |                      548.75 |
|      994 |         45094 |          40610 |             84 |                 100 |                 536.83 |                      450.94 |
|      997 |         36245 |          32656 |             20 |                 100 |                1812.25 |                      362.45 |
|      998 |         31324 |          28198 |             47 |                 100 |                 666.47 |                      313.24 |
|     1000 |         23404 |          21076 |             74 |                 100 |                 316.27 |                      234.04 |
|      996 |         22185 |          19925 |             37 |                 100 |                 599.59 |                      221.85 |
|      993 |         19341 |          17338 |           1234 |                 100 |                  15.67 |                      193.41 |
|      999 |         12076 |          10822 |             21 |                 100 |                 575.05 |                      120.76 |
|      992 |          9396 |           8478 |             18 |                 100 |                 522.00 |                       93.96 |

...

|      532 |            53 |             48 |             30 |                  31 |                   1.77 |                        1.71 |
|      564 |            53 |             47 |             30 |                  32 |                   1.77 |                        1.66 |
|      334 |            52 |             46 |             28 |                  33 |                   1.86 |                        1.58 |
|      851 |            52 |             44 |             27 |                  36 |                   1.93 |                        1.44 |
|      365 |            50 |             44 |             21 |                  30 |                   2.38 |                        1.67 |
|      407 |            50 |             46 |             31 |                  29 |                   1.61 |                        1.72 |
|      589 |            50 |             47 |             10 |                  27 |                   5.00 |                        1.85 |
|      808 |            49 |             44 |             14 |                  26 |                   3.50 |                        1.88 |
+----------+---------------+----------------+----------------+---------------------+------------------------+-----------------------------+

```

**Duplication Rate Analysis**

```sql
SELECT
    guild_id,
    COUNT(*) as total_combinations,
    ROUND(AVG(attempt_count), 2) as avg_attempts_per_combination,
    MIN(attempt_count) as min_attempts,
    MAX(attempt_count) as max_attempts,
    ROUND(STDDEV(attempt_count), 2) as stddev_attempts,
    COUNT(CASE WHEN attempt_count = 1 THEN 1 END) as single_attempt_combinations,
    COUNT(CASE WHEN attempt_count > 10 THEN 1 END) as high_duplication_combinations,
    ROUND(COUNT(CASE WHEN attempt_count > 10 THEN 1 END) * 100.0 / COUNT(*), 2) as high_duplication_percentage
FROM (
    SELECT
        guild_id,
        player_id,
        achievement_id,
        COUNT(*) as attempt_count
    FROM achievement_unlocks
    WHERE deleted_at IS NULL
    GROUP BY guild_id, player_id, achievement_id
) combination_stats
GROUP BY guild_id
ORDER BY avg_attempts_per_combination DESC;

+----------+--------------------+------------------------------+--------------+--------------+-----------------+-----------------------------+-------------------------------+-----------------------------+
| guild_id | total_combinations | avg_attempts_per_combination | min_attempts | max_attempts | stddev_attempts | single_attempt_combinations | high_duplication_combinations | high_duplication_percentage |
+----------+--------------------+------------------------------+--------------+--------------+-----------------+-----------------------------+-------------------------------+-----------------------------+
|      995 |               1694 |                        29.17 |            4 |          104 |           16.68 |                           0 |                          1509 |                       89.08 |
|     1001 |              10000 |                        28.37 |            6 |           50 |           11.41 |                           0 |                          9586 |                       95.86 |
|      997 |               1523 |                        21.44 |            3 |           99 |           12.98 |                           0 |                          1225 |                       80.43 |
|      998 |               1921 |                        14.68 |            2 |           58 |            8.11 |                           0 |                          1246 |                       64.86 |
|      996 |               1423 |                        14.00 |            3 |           73 |            7.45 |                           0 |                           922 |                       64.79 |
|      994 |               2932 |                        13.85 |            2 |           55 |            6.99 |                           0 |                          1905 |                       64.97 |
|      999 |                786 |                        13.77 |            3 |           51 |             7.6 |                           0 |                           478 |                       60.81 |
|      992 |                621 |                        13.65 |            3 |           56 |            7.41 |                           0 |                           385 |                       62.00 |
|     1000 |               1660 |                        12.70 |            3 |           53 |            6.39 |                           0 |                           995 |                       59.94 |
|      993 |               1526 |                        11.36 |            3 |           31 |            4.38 |                           0 |                           857 |                       56.16 |

...

|      839 |                 40 |                         1.30 |            1 |            2 |            0.46 |                          28 |                             0 |                        0.00 |
|      851 |                 34 |                         1.29 |            1 |            2 |            0.46 |                          24 |                             0 |                        0.00 |
|      334 |                 36 |                         1.28 |            1 |            2 |            0.45 |                          26 |                             0 |                        0.00 |
|      458 |                122 |                         1.28 |            1 |            4 |            0.56 |                          94 |                             0 |                        0.00 |
|      248 |                 54 |                         1.22 |            1 |            2 |            0.42 |                          42 |                             0 |                        0.00 |
|      867 |                 44 |                         1.18 |            1 |            2 |            0.39 |                          36 |                             0 |                        0.00 |
+----------+--------------------+------------------------------+--------------+--------------+-----------------+-----------------------------+-------------------------------+-----------------------------+

```

**Overrall duplication distribution**

```sql
SELECT
    attempt_count,
    COUNT(*) as combination_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage
FROM (
    SELECT
        player_id,
        achievement_id,
        guild_id,
        COUNT(*) as attempt_count
    FROM achievement_unlocks
    WHERE deleted_at IS NULL
    GROUP BY guild_id, player_id, achievement_id
) combination_stats
GROUP BY attempt_count
ORDER BY attempt_count;

+---------------+-------------------+------------+
| attempt_count | combination_count | percentage |
+---------------+-------------------+------------+
|             1 |            121792 |      18.26 |
|             2 |            118725 |      17.80 |
|             3 |             57616 |       8.64 |
|             4 |             57246 |       8.58 |
|             5 |             50573 |       7.58 |
|             6 |             16338 |       2.45 |
|             7 |             15618 |       2.34 |
|             8 |             15156 |       2.27 |
...
|            91 |                 3 |       0.00 |
|            92 |                 3 |       0.00 |
|            93 |                 5 |       0.00 |
|            94 |                 2 |       0.00 |
|            99 |                 1 |       0.00 |
|           104 |                 1 |       0.00 |
+---------------+-------------------+------------+
```

**Duplication rate buckets**

```sql
SELECT
    CASE
        WHEN avg_attempts <= 2 THEN 'Low Duplication (≤2 avg)'
        WHEN avg_attempts <= 5 THEN 'Medium Duplication (2-5 avg)'
        WHEN avg_attempts <= 10 THEN 'High Duplication (5-10 avg)'
        ELSE 'Very High Duplication (>10 avg)'
    END as duplication_category,
    COUNT(*) as guild_count,
    ROUND(MIN(avg_attempts), 2) as min_avg_attempts,
    ROUND(MAX(avg_attempts), 2) as max_avg_attempts,
    ROUND(AVG(total_unlocks), 0) as avg_guild_size
FROM (
    SELECT
        guild_id,
        COUNT(*) as total_unlocks,
        ROUND(AVG(attempt_count), 2) as avg_attempts
    FROM (
        SELECT
            guild_id,
            player_id,
            achievement_id,
            COUNT(*) as attempt_count
        FROM achievement_unlocks
        WHERE deleted_at IS NULL
        GROUP BY guild_id, player_id, achievement_id
    ) combination_stats
    GROUP BY guild_id
) guild_duplication_stats
GROUP BY
    CASE
        WHEN avg_attempts <= 2 THEN 'Low Duplication (≤2 avg)'
        WHEN avg_attempts <= 5 THEN 'Medium Duplication (2-5 avg)'
        WHEN avg_attempts <= 10 THEN 'High Duplication (5-10 avg)'
        ELSE 'Very High Duplication (>10 avg)'
    END
ORDER BY min_avg_attempts;

+---------------------------------+-------------+------------------+------------------+----------------+
| duplication_category            | guild_count | min_avg_attempts | max_avg_attempts | avg_guild_size |
+---------------------------------+-------------+------------------+------------------+----------------+
| Low Duplication (≤2 avg)        |         900 |             1.18 |             1.65 |            167 |
| Medium Duplication (2-5 avg)    |          90 |             3.01 |             3.38 |            757 |
| Very High Duplication (>10 avg) |          12 |            11.23 |            29.17 |          37391 |
+---------------------------------+-------------+------------------+------------------+----------------+
```

**Performance Prediction Matrix**

```sql
SELECT
    guild_id,
    total_active_unlocks,
    unique_combinations,
    avg_attempts_per_combination,
    CASE
        WHEN total_active_unlocks > 1000000 THEN 'Window Function Likely Better'
        WHEN avg_attempts_per_combination > 10 THEN 'Window Function Likely Better'
        WHEN total_active_unlocks > 100000 AND avg_attempts_per_combination > 5 THEN 'Window Function Likely Better'
        WHEN total_active_unlocks < 10000 AND avg_attempts_per_combination <= 3 THEN 'JOIN Likely Better'
        ELSE 'Requires Testing'
    END as recommended_approach,
    ROUND(total_active_unlocks / unique_combinations, 2) as duplication_ratio
FROM (
    SELECT
        guild_id,
        COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as total_active_unlocks,
        COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)) as unique_combinations,
        ROUND(COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) * 1.0 /
              COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)), 2) as avg_attempts_per_combination
    FROM achievement_unlocks
    GROUP BY guild_id
) guild_stats
ORDER BY total_active_unlocks DESC;

+----------+----------------------+---------------------+------------------------------+-------------------------------+-------------------+
| guild_id | total_active_unlocks | unique_combinations | avg_attempts_per_combination | recommended_approach          | duplication_ratio |
+----------+----------------------+---------------------+------------------------------+-------------------------------+-------------------+
|     1002 |              4761284 |              425657 |                        11.19 | Window Function Likely Better |             11.19 |
|     1001 |               283668 |               10000 |                        28.37 | Window Function Likely Better |             28.37 |
|      995 |                49422 |                1694 |                        29.17 | Window Function Likely Better |             29.17 |
|      994 |                40610 |                2932 |                        13.85 | Window Function Likely Better |             13.85 |
|      997 |                32656 |                1523 |                        21.44 | Window Function Likely Better |             21.44 |
|      998 |                28198 |                1921 |                        14.68 | Window Function Likely Better |             14.68 |
|     1000 |                21076 |                1660 |                        12.70 | Window Function Likely Better |             12.70 |
|      996 |                19925 |                1423 |                        14.00 | Window Function Likely Better |             14.00 |
|      993 |                17338 |                1526 |                        11.36 | Window Function Likely Better |             11.36 |
|      999 |                10822 |                 786 |                        13.77 | Window Function Likely Better |             13.77 |
|      992 |                 8478 |                 621 |                        13.65 | Window Function Likely Better |             13.65 |
|      991 |                 7815 |                 690 |                        11.33 | Window Function Likely Better |             11.33 |
|      965 |                 4360 |                1349 |                         3.23 | Requires Testing              |              3.23 |
|      990 |                 4336 |                1284 |                         3.38 | Requires Testing              |              3.38 |
|      983 |                 4318 |                1301 |                         3.32 | Requires Testing              |              3.32 |
...
|      589 |                   47 |                  32 |                         1.47 | JOIN Likely Better            |              1.47 |
|      334 |                   46 |                  37 |                         1.24 | JOIN Likely Better            |              1.24 |
|      407 |                   46 |                  36 |                         1.28 | JOIN Likely Better            |              1.28 |
|      818 |                   46 |                  36 |                         1.28 | JOIN Likely Better            |              1.28 |
|      365 |                   44 |                  33 |                         1.33 | JOIN Likely Better            |              1.33 |
|      808 |                   44 |                  34 |                         1.29 | JOIN Likely Better            |              1.29 |
|      851 |                   44 |                  39 |                         1.13 | JOIN Likely Better            |              1.13 |
+----------+----------------------+---------------------+------------------------------+-------------------------------+-------------------+
```

**Summary**

```sql
SELECT
    'Total Records' as metric,
    COUNT(*) as value,
    'Overall dataset size' as description
FROM achievement_unlocks
UNION ALL
SELECT
    'Active Records' as metric,
    COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as value,
    'Records that would be processed' as description
FROM achievement_unlocks
UNION ALL
SELECT
    'Unique Player-Achievement Combinations' as metric,
    COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)) as value,
    'Unique combinations across all guilds' as description
FROM achievement_unlocks
WHERE deleted_at IS NULL
UNION ALL
SELECT
    'Average Duplication Rate' as metric,
    ROUND(AVG(attempt_count), 2) as value,
    'Average attempts per player-achievement combination' as description
FROM (
    SELECT
        player_id,
        achievement_id,
        guild_id,
        COUNT(*) as attempt_count
    FROM achievement_unlocks
    WHERE deleted_at IS NULL
    GROUP BY guild_id, player_id, achievement_id
) combination_stats;

+----------------------------------------+------------+-----------------------------------------------------+
| metric                                 | value      | description                                         |
+----------------------------------------+------------+-----------------------------------------------------+
| Total Records                          | 6061665.00 | Overall dataset size                                |
| Active Records                         | 5720948.00 | Records that would be processed                     |
| Unique Player-Achievement Combinations |  633431.00 | Unique combinations across all guilds               |
| Average Duplication Rate               |       8.58 | Average attempts per player-achievement combination |
+----------------------------------------+------------+-----------------------------------------------------+
```


## The Traditional JOIN Approach

Most experienced developers reach for a join pattern to find the latest record per group:

```sql
SELECT
  achievement_unlocks.*
FROM
  achievement_unlocks
  INNER JOIN (
    SELECT
      MAX(achievement_unlocks.id) as unlock_id
    FROM
      achievement_unlocks
    WHERE
      achievement_unlocks.deleted_at IS NULL
      AND achievement_unlocks.guild_id = (?)
    GROUP BY
      achievement_unlocks.player_id,
      achievement_unlocks.achievement_id
  ) AS latest ON latest.unlock_id = achievement_unlocks.id
  INNER JOIN achievements ON achievements.id = achievement_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  (achievement_unlocks.deleted_at IS NULL)
  AND (achievement_unlocks.guild_id = (?))
```

This approach works by finding the latest unlocked achievement through the use of maximum ID for each player-achievement combination as a subquery in the first join.

With proper indexing, this performs adequately at small scale. My testing showed:

**Small dataset (50-500 records)**

```sql
SELECT
    COUNT(*) as total_unlocks,
    COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as active_unlocks,
    COUNT(DISTINCT player_id) as unique_players,
    COUNT(DISTINCT achievement_id) as unique_achievements,
    COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)) as unique_combinations,
    ROUND(COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) * 1.0 /
          COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)), 2) as avg_duplication_rate,
    MAX(created_at) as latest_activity,
    MIN(created_at) as earliest_activity
FROM achievement_unlocks
WHERE guild_id = 464;
+---------------+----------------+----------------+---------------------+---------------------+----------------------+----------------------------+----------------------------+
| total_unlocks | active_unlocks | unique_players | unique_achievements | unique_combinations | avg_duplication_rate | latest_activity            | earliest_activity          |
+---------------+----------------+----------------+---------------------+---------------------+----------------------+----------------------------+----------------------------+
|           221 |            205 |             62 |                  72 |                 144 |                 1.42 | 2025-07-16 18:54:14.002963 | 2025-01-23 21:13:25.489689 |
+---------------+----------------+----------------+---------------------+---------------------+----------------------+----------------------------+----------------------------+
```

Running the join 5x gave me the following results:

```sql
SELECT
  achievement_unlocks.*
FROM
  achievement_unlocks
  INNER JOIN (
    SELECT
      MAX(achievement_unlocks.id) as unlock_id
    FROM
      achievement_unlocks
    WHERE
      achievement_unlocks.deleted_at IS NULL
      AND achievement_unlocks.guild_id = 464
    GROUP BY
      achievement_unlocks.player_id,
      achievement_unlocks.achievement_id
  ) AS latest ON latest.unlock_id = achievement_unlocks.id
  INNER JOIN achievements ON achievements.id = achievement_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  (achievement_unlocks.deleted_at IS NULL)
  AND (achievement_unlocks.guild_id = 464)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
2448 rows in set (0.017 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
2448 rows in set (0.015 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
2448 rows in set (0.016 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
2448 rows in set (0.016 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
2448 rows in set (0.015 sec)

```

Average: (0.017 + 0.015 + 0.016 + 0.016 + 0.015) / 5 = 0.016 sec


**Medium dataset (5,000 records)**

```sql
SELECT
    COUNT(*) as total_unlocks,
    COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as active_unlocks,
    COUNT(DISTINCT player_id) as unique_players,
    COUNT(DISTINCT achievement_id) as unique_achievements,
    COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)) as unique_combinations,
    ROUND(COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) * 1.0 /
          COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)), 2) as avg_duplication_rate,
    MAX(created_at) as latest_activity,
    MIN(created_at) as earliest_activity
FROM achievement_unlocks
WHERE guild_id = 965;
+---------------+----------------+----------------+---------------------+---------------------+----------------------+----------------------------+----------------------------+
| total_unlocks | active_unlocks | unique_players | unique_achievements | unique_combinations | avg_duplication_rate | latest_activity            | earliest_activity          |
+---------------+----------------+----------------+---------------------+---------------------+----------------------+----------------------------+----------------------------+
|          4858 |           4360 |            188 |                 100 |                1349 |                 3.23 | 2025-07-20 13:31:53.470197 | 2025-01-23 20:08:56.327072 |
+---------------+----------------+----------------+---------------------+---------------------+----------------------+----------------------------+----------------------------+
```

Running the join 5x gave me the following results:

```sql
SELECT
  achievement_unlocks.*
FROM
  achievement_unlocks
  INNER JOIN (
    SELECT
      MAX(achievement_unlocks.id) as unlock_id
    FROM
      achievement_unlocks
    WHERE
      achievement_unlocks.deleted_at IS NULL
      AND achievement_unlocks.guild_id = 464
    GROUP BY
      achievement_unlocks.player_id,
      achievement_unlocks.achievement_id
  ) AS latest ON latest.unlock_id = achievement_unlocks.id
  INNER JOIN achievements ON achievements.id = achievement_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  (achievement_unlocks.deleted_at IS NULL)
  AND (achievement_unlocks.guild_id = 965)


+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
23970 rows in set (0.065 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
23970 rows in set (0.057 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
23970 rows in set (0.055 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
23970 rows in set (0.058 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
23970 rows in set (0.056 sec)

```

Average: (0.065 + 0.057 + 0.055 + 0.058 + 0.056) / 5 =  0.0582 sec


**Large dataset (237,000 records)**

```sql
SELECT
    COUNT(*) as total_unlocks,
    COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) as active_unlocks,
    COUNT(DISTINCT player_id) as unique_players,
    COUNT(DISTINCT achievement_id) as unique_achievements,
    COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)) as unique_combinations,
    ROUND(COUNT(CASE WHEN deleted_at IS NULL THEN 1 END) * 1.0 /
          COUNT(DISTINCT CONCAT(player_id, '-', achievement_id)), 2) as avg_duplication_rate,
    MAX(created_at) as latest_activity,
    MIN(created_at) as earliest_activity
FROM achievement_unlocks
WHERE guild_id = 1002;

+---------------+----------------+----------------+---------------------+---------------------+----------------------+----------------------------+----------------------------+
| total_unlocks | active_unlocks | unique_players | unique_achievements | unique_combinations | avg_duplication_rate | latest_activity            | earliest_activity          |
+---------------+----------------+----------------+---------------------+---------------------+----------------------+----------------------------+----------------------------+
|       5011697 |        4761284 |           5000 |                 100 |              425657 |                11.19 | 2025-06-04 20:34:01.874889 | 2025-04-23 14:30:59.091404 |
+---------------+----------------+----------------+---------------------+---------------------+----------------------+----------------------------+----------------------------+
1 row in set (13.790 sec)
```

```sql
SELECT
  achievement_unlocks.*
FROM
  achievement_unlocks
  INNER JOIN (
    SELECT
      MAX(achievement_unlocks.id) as unlock_id
    FROM
      achievement_unlocks
    WHERE
      achievement_unlocks.deleted_at IS NULL
      AND achievement_unlocks.guild_id = 1002
    GROUP BY
      achievement_unlocks.player_id,
      achievement_unlocks.achievement_id
  ) AS latest ON latest.unlock_id = achievement_unlocks.id
  INNER JOIN achievements ON achievements.id = achievement_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  (achievement_unlocks.deleted_at IS NULL)
  AND (achievement_unlocks.guild_id = 1002)

+---------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+
7590630 rows in set (2 min 53.922 sec)
```

So yeah, I didn't execute 5 runs because you can see the point - it is significantly slower as the data grows - requiring a different strategy.

The root cause? Let's look at the query plan:

```sql
EXPLAIN SELECT
  achievement_unlocks.*
FROM
  achievement_unlocks
  INNER JOIN (
    SELECT
      MAX(achievement_unlocks.id) as unlock_id
    FROM
      achievement_unlocks
    WHERE
      achievement_unlocks.deleted_at IS NULL
      AND achievement_unlocks.guild_id = 1002
    GROUP BY
      achievement_unlocks.player_id,
      achievement_unlocks.achievement_id
  ) AS latest ON latest.unlock_id = achievement_unlocks.id
  INNER JOIN achievements ON achievements.id = achievement_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  (achievement_unlocks.deleted_at IS NULL)
  AND (achievement_unlocks.guild_id = 1002);

+----+-------------+---------------------+------------+--------+-----------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------+---------+------------------------------------------------------------------+---------+----------+------------------------------------+
| id | select_type | table               | partitions | type   | possible_keys                                                                                                                     | key                                        | key_len | ref                                                              | rows    | filtered | Extra                              |
+----+-------------+---------------------+------------+--------+-----------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------+---------+------------------------------------------------------------------+---------+----------+------------------------------------+
|  1 | PRIMARY     | achievements        | NULL       | index  | PRIMARY                                                                                                                           | PRIMARY                                    | 8       | NULL                                                             |     100 |   100.00 | Using index                        |
|  1 | PRIMARY     | achievement_unlocks | NULL       | ref    | PRIMARY,idx_achievement_unlocks_covering_latest,index_achievement_unlocks_on_achievement_id,index_achievement_unlocks_on_guild_id | idx_achievement_unlocks_covering_latest    | 8       | gaming_achievement_system_development.achievements.id            |     312 |     5.00 | Using index condition; Using where |
|  1 | PRIMARY     | games_achievements  | NULL       | ref    | index_games_achievements_on_achievement_id,index_games_achievements_on_game_id                                                    | index_games_achievements_on_achievement_id | 8       | gaming_achievement_system_development.achievements.id            |      17 |   100.00 | NULL                               |
|  1 | PRIMARY     | games               | NULL       | eq_ref | PRIMARY                                                                                                                           | PRIMARY                                    | 8       | gaming_achievement_system_development.games_achievements.game_id |       1 |   100.00 | Using index                        |
|  1 | PRIMARY     | <derived2>          | NULL       | ref    | <auto_key0>                                                                                                                       | <auto_key0>                                | 9       | gaming_achievement_system_development.achievement_unlocks.id     |      10 |   100.00 | Using index                        |
|  2 | DERIVED     | achievement_unlocks | NULL       | ref    | idx_achievement_unlocks_covering_latest,index_achievement_unlocks_on_guild_id                                                     | index_achievement_unlocks_on_guild_id      | 8       | const                                                            | 2939991 |    10.00 | Using where; Using temporary       |
+----+-------------+---------------------+------------+--------+-----------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------+---------+------------------------------------------------------------------+---------+----------+------------------------------------+
6 rows in set, 1 warning (0.007 sec)
```

```sql
EXPLAIN ANALYZE SELECT
  achievement_unlocks.*
FROM
  achievement_unlocks
  INNER JOIN (
    SELECT
      MAX(achievement_unlocks.id) as unlock_id
    FROM
      achievement_unlocks
    WHERE
      achievement_unlocks.deleted_at IS NULL
      AND achievement_unlocks.guild_id = 1002
    GROUP BY
      achievement_unlocks.player_id,
      achievement_unlocks.achievement_id
  ) AS latest ON latest.unlock_id = achievement_unlocks.id
  INNER JOIN achievements ON achievements.id = achievement_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  (achievement_unlocks.deleted_at IS NULL)
  AND (achievement_unlocks.guild_id = 1002);

+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| EXPLAIN                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| -> Nested loop inner join  (cost=114648 rows=0) (actual time=10153..193912 rows=7.59e+6 loops=1)
    -> Nested loop inner join  (cost=44714 rows=27972) (actual time=2.47..121431 rows=85.3e+6 loops=1)
        -> Nested loop inner join  (cost=41469 rows=27972) (actual time=2.44..72141 rows=85.3e+6 loops=1)
            -> Nested loop inner join  (cost=31679 rows=1562) (actual time=2.29..16406 rows=4.76e+6 loops=1)
                -> Covering index scan on achievements using PRIMARY  (cost=10.2 rows=100) (actual time=0.121..0.717 rows=100 loops=1)
                -> Filter: (achievement_unlocks.guild_id = 1002)  (cost=285 rows=15.6) (actual time=0.329..162 rows=47613 loops=100)
                    -> Index lookup on achievement_unlocks using idx_achievement_unlocks_covering_latest (achievement_id = achievements.id), with index condition: (achievement_unlocks.deleted_at is null)  (cost=285 rows=312) (actual time=0.329..160 rows=57209 loops=100)
            -> Index lookup on games_achievements using index_games_achievements_on_achievement_id (achievement_id = achievements.id)  (cost=4.48 rows=17.9) (actual time=0.00941..0.011 rows=17.9 loops=4.76e+6)
        -> Single-row covering index lookup on games using PRIMARY (id = games_achievements.game_id)  (cost=0.016 rows=1) (actual time=465e-6..484e-6 rows=1 loops=85.3e+6)
    -> Covering index lookup on latest using <auto_key0> (unlock_id = achievement_unlocks.id)  (cost=0.25..2.5 rows=10) (actual time=778e-6..787e-6 rows=0.089 loops=85.3e+6)
        -> Materialize  (cost=0..0 rows=0) (actual time=10150..10150 rows=423913 loops=1)
            -> Table scan on <temporary>  (actual time=9599..9657 rows=423913 loops=1)
                -> Aggregate using temporary table  (actual time=9599..9599 rows=423912 loops=1)
                    -> Filter: (achievement_unlocks.deleted_at is null)  (cost=108531 rows=293999) (actual time=6.87..4433 rows=4.76e+6 loops=1)
                        -> Index lookup on achievement_unlocks using index_achievement_unlocks_on_guild_id (guild_id = 1002)  (cost=108531 rows=2.94e+6) (actual time=6.87..4248 rows=5.01e+6 loops=1)
 |
+------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (3 min 14.759 sec)
```

There are 4 primary bottlenecks with the query plan:

**Massive Cartesian Product Formation**

The query is creating an enormous intermediate result set of 85.3 million rows before applying the final filter. This happens because:

- The subquery produces 423,913 distinct records
- Each record then gets joined with multiple tables, exploding the result set
- The final filtering step (matching with the derived table) only retains ~7.59 million rows

> What is a cartesian product?
>
> A Cartesian product happens when you join tables and get way more rows than you expect - essentially every row from one table gets matched with every row from another table.
Think of it like this: if you have a table of 3 people and a table of 4 pizza toppings, a Cartesian product would give you 3 × 4 = 12 combinations (every person paired with every topping), even if that doesn't make logical sense.
>
> The database is essentially saying: "I'll join everything together first, then figure out which ones you actually want." Instead of: "Let me figure out what you want first, then only create those combinations."
It's like making every possible sandwich combination in a deli, then throwing away the ones nobody ordered, instead of just making the sandwiches people actually want.

**Inefficient Join Order**

MySQL is processing tables in a suboptimal sequence:

- Starting with achievements (100 rows)
- Then achievement_unlocks (filtering to 4.76M rows)
- Then games_achievements (expanding to 85.3M rows)
- Finally applying the derived table filter

**Expensive Subquery Materialization**

The derived table operation is costly:
`-> Materialize (cost=0..0 rows=0) (actual time=10150..10150 rows=423913 loops=1)`
This takes over 10 seconds just to build the temporary table with MAX(id) values.

**Redundant Filtering**

The query applies `guild_id = 1002` and `deleted_at IS NULL` filters in multiple places, but the join order means these filters aren't being applied early enough to reduce the working set size.

We needed a fundamentally different approach then — one that could handle our production scale without the exponential performance degradation to the small and medium datasets.

## Enter Window Functions

MySQL 8.0 introduced <a href="https://dev.mysql.com/doc/refman/9.4/en/window-functions.html" target="_blank">window functions</a>, providing an elegant solution:


```sql
SELECT * FROM (
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY player_id, achievement_id
               ORDER BY id DESC
           ) AS rn
    FROM achievement_unlocks
    WHERE
      deleted_at IS NULL
      AND guild_id = (?)
      AND achievement_id IN (?)
) AS latest_achievement_unlocks
WHERE rn = 1;
```

Let's see what the initial results looked like following the same strategy as the joins above:


**Small dataset (50-500 records)**

First we need to find all eligible achievement ids.

```sql
SELECT
  DISTINCT achievements.id
FROM
  achievements
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
  INNER JOIN gameships ON gameships.game_id = games.id
  INNER JOIN achievement_categories ON achievement_categories.id = gameships.achievement_category_id
WHERE
  achievement_categories.guild_id = 464;

+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| achievement_ids                                                                                                                                                                                                                                                                                     |
+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100 |
+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+

-- NOTE: The above is nicely formatted due to me using GROUP_CONAT for this article only.
```

Running the window function 5x gave me the following results:

```sql
SELECT outer_unlocks.*
FROM (
  SELECT inner_unlocks.*
  FROM (
    SELECT achievement_unlocks.*,
            ROW_NUMBER() OVER (PARTITION BY player_id, achievement_id ORDER BY id DESC) AS rn
    FROM achievement_unlocks
    WHERE deleted_at IS NULL
      AND guild_id = 464
      AND achievement_id IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100)
  ) inner_unlocks
  WHERE rn = 1
) AS outer_unlocks
INNER JOIN achievements ON achievements.id = outer_unlocks.achievement_id
INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  outer_unlocks.deleted_at IS NULL;

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
2448 rows in set (0.020 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
2448 rows in set (0.023 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
2448 rows in set (0.021 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
2448 rows in set (0.023 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
2448 rows in set (0.020 sec)
```

JOIN Average: (0.017 + 0.015 + 0.016 + 0.016 + 0.015) / 5 = 0.016 sec
Window Function Average: (0.020 + 0.023 + 0.021 +  0.023 + 0.020) / 5 = 0.024 sec

❌ In this case the JOIN won.

**Medium dataset (5,000 records)**

```sql
SELECT
  DISTINCT achievements.*
FROM
  achievements
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
  INNER JOIN gameships ON gameships.game_id = games.id
  INNER JOIN achievement_categories ON achievement_categories.id = gameships.achievement_category_id
WHERE
  achievement_categories.guild_id = 965;

+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| achievement_ids                                                                                                                                                                                                                                                                                     |
+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100 |
+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
```

Running the join 5x gave me the following results:

```sql
SELECT
  outer_unlocks.*
FROM
  (
    SELECT
      inner_unlocks.*
    FROM
      (
        SELECT
          achievement_unlocks.*,
          ROW_NUMBER() OVER (
            PARTITION BY player_id,
            achievement_id
            ORDER BY
              id DESC
          ) AS rn
        FROM
          achievement_unlocks
        WHERE
          deleted_at IS NULL
          AND guild_id = 965
          AND achievement_id IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100)
      ) inner_unlocks
    WHERE
      rn = 1
  ) AS outer_unlocks
  INNER JOIN achievements ON achievements.id = outer_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  outer_unlocks.deleted_at IS NULL;

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
23970 rows in set (0.079 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
23970 rows in set (0.087 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
23970 rows in set (0.082 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
23970 rows in set (0.075 sec)

+--------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
23970 rows in set (0.082 sec)
```

JOIN Average: (0.065 + 0.057 + 0.055 + 0.058 + 0.056) / 5 =  0.0582 sec
Window Function Average: (0.079 + 0.087 + 0.082 + 0.075 + 0.082) / 5 = 0.081 sec

❌ In this case the JOIN won.

**Large dataset (237,000 records)**

```sql
SELECT
  DISTINCT achievements.*
FROM
  achievements
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
  INNER JOIN gameships ON gameships.game_id = games.id
  INNER JOIN achievement_categories ON achievement_categories.id = gameships.achievement_category_id
WHERE
  achievement_categories.guild_id = 1002;

+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| achievement_ids                                                                                                                                                                                                                                                                                     |
+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100 |
+-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
```

Running the join 5x gave me the following results:

```sql
SELECT
  outer_unlocks.*
FROM
  (
    SELECT
      inner_unlocks.*
    FROM
      (
        SELECT
          achievement_unlocks.*,
          ROW_NUMBER() OVER (
            PARTITION BY player_id,
            achievement_id
            ORDER BY
              id DESC
          ) AS rn
        FROM
          achievement_unlocks
        WHERE
          deleted_at IS NULL
          AND guild_id = 1002
          AND achievement_id IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100)
      ) inner_unlocks
    WHERE
      rn = 1
  ) AS outer_unlocks
  INNER JOIN achievements ON achievements.id = outer_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  outer_unlocks.deleted_at IS NULL;

+---------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
7590630 rows in set (24.816 sec)

+---------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
7590630 rows in set (26.207 sec)

+---------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
7590630 rows in set (25.766 sec)

+---------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
7590630 rows in set (26.346 sec)

+---------+-----------+----------------+----------+----------------------------+---------------------+------------+----------------------------+----------------------------+----+
7590630 rows in set (26.877 sec)
```

JOIN: 174 sec
Window Function Average: (24.816 + 26.207 + 25.766 + 26.346 + 26.877) / 5 = 26.004 sec
Improvement: ((174 - 26) / 174) × 100 = 85.06%

🟢 Window Function Wins! With a 85% improvement over the JOIN.

Ok. So JOINS work perfectly for small to medium datasets but NOT for large scale datasets. But why?

Let's look at the query plan and compare to the join to better understand why.

```sql
EXPLAIN SELECT
  outer_unlocks.*
FROM
  (
    SELECT
      inner_unlocks.*
    FROM
      (
        SELECT
          achievement_unlocks.*,
          ROW_NUMBER() OVER (
            PARTITION BY player_id,
            achievement_id
            ORDER BY
              id DESC
          ) AS rn
        FROM
          achievement_unlocks
        WHERE
          deleted_at IS NULL
          AND guild_id = 965
          AND achievement_id IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100)
      ) inner_unlocks
    WHERE
      rn = 1
  ) AS outer_unlocks
  INNER JOIN achievements ON achievements.id = outer_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  outer_unlocks.deleted_at IS NULL;

+----+-------------+---------------------+------------+--------+---------------------------------------------------------------------------------------------------------------------------+--------------------------------------------+---------+------------------------------------------------------------------+------+----------+-----------------------------+
| id | select_type | table               | partitions | type   | possible_keys                                                                                                             | key                                        | key_len | ref                                                              | rows | filtered | Extra                       |
+----+-------------+---------------------+------------+--------+---------------------------------------------------------------------------------------------------------------------------+--------------------------------------------+---------+------------------------------------------------------------------+------+----------+-----------------------------+
|  1 | PRIMARY     | <derived3>          | NULL       | ALL    | NULL                                                                                                                      | NULL                                       | NULL    | NULL                                                             |  485 |     1.00 | Using where                 |
|  1 | PRIMARY     | achievements        | NULL       | eq_ref | PRIMARY                                                                                                                   | PRIMARY                                    | 8       | inner_unlocks.achievement_id                                     |    1 |   100.00 | Using index                 |
|  1 | PRIMARY     | games_achievements  | NULL       | ref    | index_games_achievements_on_achievement_id,index_games_achievements_on_game_id                                            | index_games_achievements_on_achievement_id | 8       | inner_unlocks.achievement_id                                     |   17 |   100.00 | NULL                        |
|  1 | PRIMARY     | games               | NULL       | eq_ref | PRIMARY                                                                                                                   | PRIMARY                                    | 8       | gaming_achievement_system_development.games_achievements.game_id |    1 |   100.00 | Using index                 |
|  3 | DERIVED     | achievement_unlocks | NULL       | ref    | idx_achievement_unlocks_covering_latest,index_achievement_unlocks_on_achievement_id,index_achievement_unlocks_on_guild_id | index_achievement_unlocks_on_guild_id      | 8       | const                                                            | 4858 |    10.00 | Using where; Using filesort |
+----+-------------+---------------------+------------+--------+---------------------------------------------------------------------------------------------------------------------------+--------------------------------------------+---------+------------------------------------------------------------------+------+----------+-----------------------------+
5 rows in set, 2 warnings (0.370 sec)
```

```sql
EXPLAIN ANALYZE SELECT
  outer_unlocks.*
FROM
  (
    SELECT
      inner_unlocks.*
    FROM
      (
        SELECT
          achievement_unlocks.*,
          ROW_NUMBER() OVER (
            PARTITION BY player_id,
            achievement_id
            ORDER BY
              id DESC
          ) AS rn
        FROM
          achievement_unlocks
        WHERE
          deleted_at IS NULL
          AND guild_id = 965
          AND achievement_id IN (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100)
      ) inner_unlocks
    WHERE
      rn = 1
  ) AS outer_unlocks
  INNER JOIN achievements ON achievements.id = outer_unlocks.achievement_id
  INNER JOIN games_achievements ON games_achievements.achievement_id = achievements.id
  INNER JOIN games ON games.id = games_achievements.game_id
WHERE
  outer_unlocks.deleted_at IS NULL;

+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| EXPLAIN                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
| -> Nested loop inner join  (cost=120 rows=86.9) (actual time=45.7..77.5 rows=23970 loops=1)
    -> Nested loop inner join  (cost=89.2 rows=86.9) (actual time=45.7..63.8 rows=23970 loops=1)
        -> Nested loop inner join  (cost=58.8 rows=4.85) (actual time=45.6..47 rows=1341 loops=1)
            -> Filter: ((inner_unlocks.rn = 1) and (inner_unlocks.deleted_at is null))  (cost=57.1 rows=4.85) (actual time=45.6..46.1 rows=1341 loops=1)
                -> Table scan on inner_unlocks  (cost=1119..1183 rows=4858) (actual time=45.6..45.9 rows=4360 loops=1)
                    -> Materialize  (cost=1119..1119 rows=4858) (actual time=45.6..45.6 rows=4360 loops=1)
                        -> Window aggregate: row_number() OVER (PARTITION BY achievement_unlocks.player_id,achievement_unlocks.achievement_id ORDER BY achievement_unlocks.id desc )   (cost=0 rows=4858) (actual time=36.4..43.4 rows=4360 loops=1)
                            -> Sort: achievement_unlocks.player_id, achievement_unlocks.achievement_id, achievement_unlocks.id DESC  (cost=4906 rows=4858) (actual time=36.4..38.9 rows=4360 loops=1)
                                -> Filter: ((achievement_unlocks.deleted_at is null) and (achievement_unlocks.achievement_id in (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,82,83,84,85,86,87,88,89,90,91,92,93,94,95,96,97,98,99,100)))  (cost=4906 rows=4858) (actual time=1.79..23.8 rows=4360 loops=1)
                                    -> Index lookup on achievement_unlocks using index_achievement_unlocks_on_guild_id (guild_id = 965)  (cost=4906 rows=4858) (actual time=1.79..22.8 rows=4858 loops=1)
            -> Single-row covering index lookup on achievements using PRIMARY (id = inner_unlocks.achievement_id)  (cost=0.271 rows=1) (actual time=606e-6..627e-6 rows=1 loops=1341)
        -> Index lookup on games_achievements using index_games_achievements_on_achievement_id (achievement_id = inner_unlocks.achievement_id)  (cost=4.85 rows=17.9) (actual time=0.0102..0.0118 rows=17.9 loops=1341)
    -> Single-row covering index lookup on games using PRIMARY (id = games_achievements.game_id)  (cost=0.251 rows=1) (actual time=462e-6..481e-6 rows=1 loops=23970)
 |
+---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------+
1 row in set (0.091 sec)
```

But why?

## Understanding the Performance Characteristics

### JOIN Approach Complexity: O(n log n + n)

The JOIN must:
1. Scan all records for the organization (n records)
2. GROUP BY to find MAX(id) — requires sorting or hash aggregation (n log n)
3. Join back to retrieve full records (n seeks)

At scale, this creates massive intermediate result sets. The execution plan reveals:

```sql
EXPLAIN ANALYZE shows:
- Temporary table: Yes
- Using filesort: Yes
- Rows examined: 5,000,000 (twice!)
```

### Window Function Complexity: O(n log n)

The window function:
1. Scans records once (n records)
2. Sorts within partitions (n log n, but more efficient)
3. Assigns row numbers during the scan
4. Filters results

The key advantage: **single pass through the data**.

## Critical Index Design

The performance difference hinges on proper indexing:

```sql
-- Optimal for window functions
CREATE INDEX idx_window_function_optimal ON achievement_unlocks
(guild_id, deleted_at, player_id, achievement_id, id DESC);

-- Optimal for JOIN approach
CREATE INDEX idx_join_approach ON achievement_unlocks
(guild_id, deleted_at, player_id, achievement_id);
```

The window function index column order is critical:
1. `guild_id, deleted_at` — WHERE clause filters
2. `player_id, achievement_id` — PARTITION BY columns
3. `id DESC` — ORDER BY column

## When Window Functions Truly Dominate

Our testing revealed window functions excel in complex scenarios:

### Scenario 1: Top N Records per Group

```sql
-- Get top 3 attempts per player-achievement
-- Window Function: 4.408s
-- JOIN approach: TIMEOUT after 10s
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (
        PARTITION BY player_id, achievement_id
        ORDER BY id DESC
    ) AS rn
    FROM achievement_unlocks
    WHERE guild_id = 1001 AND deleted_at IS NULL
) t WHERE rn <= 3;
```

The JOIN equivalent requires correlated subqueries that scale exponentially.

### Scenario 2: Ranking and Analytics

```sql
-- Rank players by completion percentage
-- Window Function: 2.497s
-- JOIN approach: Not practically possible
SELECT player_id, achievement_id, progress_percentage,
       RANK() OVER (
           PARTITION BY achievement_id
           ORDER BY progress_percentage DESC
       ) as `rank`
FROM achievement_unlocks
WHERE guild_id = 1001 AND deleted_at IS NULL;
```

### Scenario 3: Inter-row Comparisons

```sql
-- Compare with previous attempt
-- Window Function: 13.054s
-- JOIN approach: Would require multiple self-joins
SELECT player_id, achievement_id, progress_percentage,
       LAG(progress_percentage) OVER (
           PARTITION BY player_id, achievement_id
           ORDER BY created_at
       ) as previous_progress
FROM achievement_unlocks
WHERE guild_id = 1001 AND deleted_at IS NULL;
```

## The Service Layer Pattern

In production, we implemented a strategy pattern to choose the optimal approach:

```ruby
class AchievementQueryStrategy
  def initialize(guild_id)
    @guild_id = guild_id
  end

  def latest_unlocks
    # Check data characteristics
    if should_use_window_function?
      latest_unlocks_with_window_function
    else
      latest_unlocks_with_joins
    end
  end

  private

  def should_use_window_function?
    # Use window functions when:
    # 1. Dataset > 1M records
    # 2. High duplication rate (>5 attempts per combination)
    # 3. Need more than just the latest record
    stats = analyze_dataset

    stats[:total_records] > 1_000_000 ||
    stats[:avg_duplication] > 5 ||
    stats[:complex_requirements]
  end

  def latest_unlocks_with_window_function
    sql = <<-SQL
      SELECT * FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                 PARTITION BY player_id, achievement_id
                 ORDER BY id DESC
               ) AS rn
        FROM achievement_unlocks
        WHERE guild_id = ?
          AND deleted_at IS NULL
      ) ranked
      WHERE rn = 1
    SQL

    AchievementUnlock.find_by_sql([sql, @guild_id])
  end

  def latest_unlocks_with_joins
    # JOIN implementation for smaller datasets
  end
end
```

## Performance Tuning Insights

Through extensive benchmarking, we discovered several critical factors:

### 1. Data Distribution Matters

```sql
-- Check duplication rate
SELECT
    AVG(cnt) as avg_attempts,
    MAX(cnt) as max_attempts
FROM (
    SELECT COUNT(*) as cnt
    FROM achievement_unlocks
    WHERE guild_id = 1001 AND deleted_at IS NULL
    GROUP BY player_id, achievement_id
) t;
```

- **Low duplication (1-2 attempts)**: JOINs often win
- **High duplication (10+ attempts)**: Window functions dominate

### 2. Result Set Size Impact

Returning large result sets can mask query performance. Always test with COUNT(*) first:

```sql
-- Test query performance without result transfer overhead
SELECT COUNT(*) FROM ( /* your query here */ ) t;
```

### 3. MySQL Configuration

Key settings that affect window function performance:
- `sort_buffer_size`: Increase for large partitions
- `tmp_table_size`: Critical for window function temporary tables
- `join_buffer_size`: Affects JOIN approach performance

## Surprising Findings

Our investigation revealed several counterintuitive insights:

1. **Modern MySQL optimizes GROUP BY extremely well** — with proper indexes, the JOIN approach can outperform window functions for simple "latest record" queries up to ~1M records.

2. **Window functions have overhead** — the partitioning and ranking process isn't free. For small datasets with low duplication, this overhead exceeds the benefit.

3. **Index design is everything** — a poorly indexed window function query will perform worse than a well-indexed JOIN, regardless of data size.

## Production Results

After implementing the strategy pattern in production:
- **Query time for largest organization**: 30s → 1.2s (25x improvement)
- **Database CPU usage**: Reduced by 60%
- **Connection pool stability**: No more exhaustion during peak hours

The key was recognizing that one size doesn't fit all — we now use JOINs for ~70% of queries (smaller organizations) and window functions for the remaining 30% (large organizations with high data duplication).

## Key Takeaways

1. **Window functions aren't always faster** — profile your specific data patterns
2. **The inflection point is around 1M records** with moderate duplication
3. **Complex analytical queries always favor window functions** — ranking, running totals, inter-row comparisons
4. **Index design must match your query pattern** — column order matters tremendously
5. **Consider a hybrid approach** — use the right tool for each scenario

## Conclusion

The journey from a timing-out query to a sub-second response taught us that database optimization is rarely about finding a silver bullet. Window functions are powerful tools, but understanding when and how to use them — versus traditional approaches — is what separates good solutions from great ones.

For those interested in experimenting with these patterns, the complete demo application with realistic seed data is available at [github.com/alvincrespo/gaming_achievement_system](https://github.com/alvincrespo/gaming_achievement_system). The repository includes benchmarking tools and seed data generators to reproduce these performance characteristics at various scales.

Remember: always measure with your actual data. The beauty of SQL optimization is that the same query can have vastly different performance characteristics based on data distribution, and the only way to know for sure is to test.

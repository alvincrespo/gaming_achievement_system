# Gaming Achievement System - MySQL Query Optimization Demo

This repository contains a fully functional Ruby on Rails application that demonstrates MySQL query optimization techniques, specifically comparing traditional [JOIN](https://dev.mysql.com/doc/refman/8.4/en/join.html) approaches with [Window Functions](https://dev.mysql.com/doc/refman/8.4/en/window-functions-usage.html) for finding the latest record per group at scale.

## 📖 Blog Post

For a detailed analysis of the query optimization techniques demonstrated in this application, read the accompanying blog post: [A Deep Dive into MySQL Query Optimization at Scale](https://alvincrespo.hashnode.dev/mysql-query-optimization-at-scale)

**Key Findings:**
- JOINs perform well for small datasets (<10K records) with low duplication
- Window Functions excel at large datasets (>1M records) with high duplication
- The inflection point depends on data distribution and duplication rates
- At enterprise scale, Window Functions can be 85% faster

## 🎮 Features

- **Real-world data model**: Gaming guilds, players, and achievement tracking
- **Realistic data patterns**: Varying guild sizes and achievement attempt rates
- **Built-in benchmarking**: Compare JOIN vs Window Function performance
- **Enterprise-scale testing**: Generate millions of records to simulate production loads
- **Performance analytics**: Detailed query analysis and statistics

## 📋 Prerequisites

- Ruby 3.4.4
- Rails 8.0.2
- MySQL 8.0+ (required for Window Functions)
- Node.js (for JavaScript runtime)

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/alvincrespo/gaming_achievement_system.git
cd gaming_achievement_system

# Install dependencies
bundle install

# Setup database
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed    # Creates ~6M records

# Start development server
bin/dev
```

Visit http://localhost:3000 to view the application.

## 🗄️ Data Model

The application models a gaming achievement system with these core entities:

- **Players**: Users who earn achievements
- **Guilds**: Gaming organizations/clans
- **Games**: Video games in the system
- **Achievements**: Accomplishments players can earn
- **AchievementUnlocks**: Junction table tracking player progress (multiple attempts per achievement)

The key challenge: Players make multiple attempts at achievements, creating 10-50 records per player-achievement combination. Queries need to find the most recent attempt for each combination efficiently.

## 🌱 Seed Data

### Standard Seed (Included in `db:seed`)

Creates a realistic distribution of gaming data:

```
- 1,000 guilds
  - 900 small guilds (50-500 records, 1-2 attempts per achievement)
  - 90 medium guilds (500-5K records, 2-5 attempts per achievement)
  - 10 mega guilds (5K-60K records, 5-20 attempts per achievement)
- 50,000 players
- 100 achievements
- 50 games
- ~6 million achievement unlock records
```

**Special Guild**: "Window Function Demo Guild" (ID: 1001)
- 200 players × 50 achievements × 10-50 attempts = ~300K records
- Optimized to demonstrate Window Function advantages

### Enterprise-Scale Data

For production-scale testing, generate 5-10 million records:

```bash
# Creates "Mega Scale Demo Guild" with 5M+ records
rails gaming:create_large_scale_demo

# Expected output:
# - 5,000 players
# - 100 achievements
# - 10-50 attempts per combination
# - Total: ~5-10 million records
```

This simulates real enterprise patterns where:
- 50% of users have few attempts (1-5)
- 30% have moderate attempts (5-15)
- 15% have many attempts (15-30)
- 5% have extreme attempts (30-50)

## 📊 Benchmarking Performance

### Basic Benchmarking

Test with the Window Function Demo Guild:

```bash
rails gaming:benchmark guild_id=1001
```

### Enterprise-Scale Benchmarking

After creating large-scale data:

```bash
rails gaming:benchmark_large_scale guild_id=1002
```

This runs multiple iterations and provides:
- Average query times
- Row counts
- Performance comparison
- Execution plan analysis

### Example Output

```
Guild 1002 Statistics:
  Total records: 5,011,697
  Active records: 4,761,284
  Unique combinations: 425,657
  Average duplicates: 11.2

Window Function Average: 26.004s
JOIN Approach Average: 174.000s

✅ Window function is 6.69x faster!
```

## 💡 SQL Query Examples

### Traditional JOIN Approach

```sql
SELECT achievement_unlocks.*
FROM achievement_unlocks
INNER JOIN (
  SELECT MAX(id) as unlock_id
  FROM achievement_unlocks
  WHERE deleted_at IS NULL
    AND guild_id = ?
  GROUP BY player_id, achievement_id
) AS latest ON latest.unlock_id = achievement_unlocks.id
```

### Window Function Approach

```sql
SELECT * FROM (
  SELECT *,
    ROW_NUMBER() OVER (
      PARTITION BY player_id, achievement_id
      ORDER BY id DESC
    ) AS rn
  FROM achievement_unlocks
  WHERE deleted_at IS NULL
    AND guild_id = ?
) AS ranked
WHERE rn = 1
```

## 🛠️ Development Commands

```bash
# Run development server with Tailwind CSS watcher
bin/dev

# Database operations
bin/rails db:migrate
bin/rails db:rollback
bin/rails db:reset       # Drop, create, migrate, seed

# Code quality
bin/rubocop              # Ruby linting
bin/brakeman             # Security analysis

# Testing (when implemented)
bin/rails test

# Console
bin/rails console
```

## ⚙️ MySQL Configuration

For optimal Window Function performance, consider these settings:

```sql
-- Check your MySQL version (must be 8.0+)
SELECT VERSION();

-- Recommended settings
SET sort_buffer_size = 256M;
SET tmp_table_size = 512M;
SET max_heap_table_size = 512M;
```

## 🔍 Analyzing Your Queries

Use these tools to understand query performance: [EXPLAIN](https://dev.mysql.com/doc/refman/8.4/en/using-explain.html), [EXPLAIN ANALYZE](https://dev.mysql.com/doc/refman/8.4/en/explain.html#explain-analyze) and [SHOW INDEX](https://dev.mysql.com/doc/refman/8.4/en/show-index.html).

```sql
-- Execution plan
EXPLAIN SELECT ...

-- Detailed execution with timing
EXPLAIN ANALYZE SELECT ...

-- Check index usage
SHOW INDEX FROM achievement_unlocks;
```

## 🐛 Troubleshooting

### MySQL Version Error
```
Error: Window functions are not supported
```
**Solution**: Upgrade to MySQL 8.0 or higher

### Slow Seed Generation
The seed creates millions of records. On slower hardware:
- Use `rails db:seed RAILS_LOG_TO_STDOUT=true` to see progress
- Consider reducing record counts in `db/seeds.rb`

### Memory Issues During Benchmarking
Large datasets require significant memory:
- Increase MySQL buffer pool size
- Run benchmarks on smaller guilds first
- Use the COUNT-only queries to avoid result set transfer

## 📈 Performance Insights

The application demonstrates that:

1. **Data distribution matters more than size**: High duplication rates favor Window Functions
2. **Modern MySQL optimizes GROUP BY well**: JOINs can outperform Window Functions for simple cases
3. **Complex analytical queries always favor Window Functions**: Top-N per group, running totals, etc.
4. **Index design is critical**: But algorithm choice matters more at scale

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is open source and available under the [MIT License](LICENSE).

## 🙏 Acknowledgments

- MySQL team for Window Function implementation
- Rails community for the excellent framework
- All contributors to the libraries used in this project

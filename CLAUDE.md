# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Gaming Achievement System

A Ruby on Rails 8.0.2 application for tracking gaming achievements across guilds, games, and players.

### Development Commands

```bash
# Start development server (Rails + Tailwind CSS watcher)
bin/dev

# Database operations
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed

# Code quality
bin/rubocop              # Ruby linting/style
bin/brakeman             # Security analysis

# Asset compilation
bin/rails tailwindcss:build
bin/rails assets:precompile
```

### Technology Stack

- **Rails 8.0.2** with Ruby 3.4.4
- **MySQL 8.0** database with utf8mb4 charset
- **Hotwire** (Turbo + Stimulus) for frontend interactivity
- **Tailwind CSS** for styling
- **Solid trilogy** (Queue, Cache, Cable) for infrastructure
- **Kamal** for containerized deployment

### Architecture Overview

This is a guild-centric gaming achievement system with the following domain model:

#### Core Entities
- **Players**: Users who earn achievements (`username`, `email`, `level`, `total_points`)
- **Guilds**: Organizations/groups (`name`, `description`, `tag`)
- **Games**: Video games in the system (`name`, `genre`, `platform`)
- **Achievements**: Individual accomplishments (`name`, `points`, `rarity`)

#### Key Relationships
- **AchievementUnlocks**: Central junction tracking when players unlock achievements within guilds
- **GamesAchievements**: Links games to their available achievements
- **Guildships**: Additional guild metadata and organization
- **AchievementCategories**: Categories of achievements belonging to guilds

### Database Considerations

- **Multi-database setup** for production (separate cache, queue, cable databases)
- **Optimized indexes** on achievement_unlocks for performance queries
- **Soft deletes** implemented on achievement_unlocks with `deleted_at`
- **Guild-scoped operations** - most queries should consider guild context

### Current State

The application is in early scaffolding stage with:
- ✅ Database schema and migrations defined
- ✅ Basic Rails models created (no relationships/validations yet)
- ✅ Production deployment configuration
- ❌ No test suite configured
- ❌ No controllers, views, or routes implemented
- ❌ No model relationships or validations defined

### Development Notes

- Use `bin/dev` for development to get both Rails server and Tailwind CSS watching
- All models are currently bare - add relationships, validations, and business logic as needed
- The system is designed for multi-tenancy through guild scoping
- Achievement unlocking is the core business operation involving players, achievements, and guilds
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Lit** is a Rails i18n Web Interface - a database-powered internationalization (i18n) backend with a web GUI for managing translations. It runs as a Rails engine, intercepting `I18n.t()` calls and storing translations in a database instead of YAML files.

## Common Commands

### Test Execution
```bash
# Run all tests across all Rails versions
bundle exec appraisal rake

# Run tests for a specific Rails version
bundle exec appraisal rails-5.2 rake
bundle exec appraisal rails-6.1 rake
bundle exec appraisal rails-7.2 rake

# Run tests with specific storage backend
LIT_STORAGE=redis bundle exec rake test    # Uses Redis
LIT_STORAGE=hash bundle exec rake test     # Uses in-memory hash

# Run a single test file
bundle exec appraisal rails-7.2 ruby -Itest test/unit/localization_test.rb
```

### Initial Setup
```bash
bundle install
bundle exec appraisal install
cp test/dummy/config/database.yml.sample test/dummy/config/database.yml
RAILS_ENV=test bundle exec appraisal rails-5.2 rake db:setup
```

### Rake Tasks
```bash
# Export translations
rake lit:export FORMAT=csv LOCALES=en,pl OUTPUT=export.csv
rake lit:export_splitted FORMAT=yaml

# Import translations
rake lit:import FILE=stuff.csv LOCALES=en,pl SKIP_NIL=1

# Pre-load keys without overwriting existing DB values
rake lit:warm_up_keys FILES=config/locales/en.yml LOCALES=en
```

## Architecture

### Core Components

1. **I18n Backend** (`lib/lit/i18n_backend.rb`) - Custom `I18n::Backend::Simple` implementation that intercepts all Rails `I18n.t()` calls, stores translations in database, and auto-creates missing keys.

2. **Cache Layer** (`lib/lit/cache.rb`) - Hybrid caching supporting Redis (production) or in-memory hash (development). Thread-local cache per request with optional hits counter.

3. **Rails Engine** (`lib/lit/engine.rb`) - Isolated namespace `Lit::` with auto-loaded controllers, models, views, and asset precompilation.

### Data Models

- `Lit::Locale` - Language locales (en, pl, etc.)
- `Lit::LocalizationKey` - Translation key definitions (i18n key paths)
- `Lit::Localization` - Translated values per key/locale pair
- `Lit::LocalizationVersion` - Version history of translations
- `Lit::Source` - Remote sync sources
- `Lit::IncommingLocalization` - Incoming translations during sync

### Key Patterns

- Keys ending with `_html` get WYSIWYG editor support
- Array types (e.g., `date.abbr_day_names`) are fully supported
- Cloud translation providers extend `Lit::CloudTranslation::Providers::Base`
- Storage adapters in `lib/lit/adapters/` (redis_storage.rb, hash_storage.rb)

### Configuration

Main configuration options are set in `lib/lit.rb` as module attributes:
- `key_value_engine` - 'redis' or 'hash'
- `redis_url` - Redis connection string
- `api_enabled` / `api_key` - JSON API settings
- `store_request_info` - Track where keys are used
- `hits_counter_enabled` - Usage analytics (Redis only)

## Testing Environment

- Uses Minitest with Capybara for integration tests
- VCR/WebMock for HTTP request recording (cloud translation tests)
- Database Cleaner for test isolation
- Test dummy app in `test/dummy/`
- Appraisals for Rails version compatibility (5.2, 6.0, 6.1, 7.2)

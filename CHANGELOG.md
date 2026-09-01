# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

## [1.2.6] - 2026-09-01
### Changed
- AI translated tab: back to one table per localization key, each with its own header row,
  matching the Translate! list. The single combined table was denser but did not look like
  the rest of the interface.

## [1.2.5] - 2026-09-01
### Fixed
- AI translated tab: the 1.2.3 rework renamed the row classes but left the JavaScript and
  the accept / destroy / update .js.erb responses pointing at the old ones, so inline
  editing did nothing and an accepted row stayed on screen until reload. Selectors
  realigned and pinned by tests asserting the view and the javascript responses agree.
- The tag multiselect initialises at width 100%, which is right in the sidebar but made
  the tab's horizontal toolbar wrap onto three lines. Constrained inside the toolbar.

### Changed
- Compacted the row actions and toolbar buttons, and handed the table's borders, striping
  and font size back to Bootstrap so the tab matches the Translate! list.

## [1.2.4] - 2026-09-01
### Changed
- AI translated tab: dropped the per-row provider label (it is always the same agent, so
  it carried no information) and put the table on one type scale — cell text and
  proposals at one size, tag chips and status badges sharing a second.

## [1.2.3] - 2026-09-01
### Changed
- Reworked the "AI translated" tab after review: one dense table instead of a table per
  key, so a reviewer sees roughly a dozen strings per screen instead of three; the
  explanation collapsed behind "How this works"; real buttons for Accept / edit / Reject
  and for Accept all / Reject all, with the proposal count beside them; clickable tag
  chips; 30 rows per page instead of Kaminari's host default.

## [1.2.2] - 2026-09-01
### Fixed
- The `refresh_keys` concurrency guard was backed by `Rails.cache`, which a host may
  legitimately configure as a `NullStore` (elvium does exactly that in development). The
  guard then silently never held and every request launched another full YAML scan. It now
  uses Lit's own Redis store when the redis key-value engine is active, keyed with the
  configured storage prefix, and falls back to `Rails.cache` otherwise.

## [1.2.1] - 2026-09-01
### Fixed
- The two new migrations declared `ActiveRecord::Migration[4.2]`, matching the older
  migrations in this gem. In 4.2 compatibility mode new tables get a plain `integer`
  primary key, which host applications running `online_migrations` reject as an ID
  wraparound risk. They now declare `Migration[5.2]` (the gem's minimum supported Rails),
  so primary keys are `bigint`. Foreign key columns stay `integer` because the existing
  lit tables they reference have `integer` primary keys; `lit_localization_key_tags.tag_id`
  is `bigint` to match the new `lit_tags.id`.

## [1.2.0] - 2026-09-01
### Added
- AI translation suggestions: an authorized agent can push proposed translations
  through a new token-guarded API, and a human reviews them on the new
  "AI translated" tab before anything reaches the application. A proposal shows the
  current value next to the proposal, can be edited, accepted one at a time or in
  bulk (in the background), or rejected. Accepting writes the translation and marks
  it ready for synchronization.
  - `Lit.ai_api_enabled` and `Lit.ai_api_key` - both required; the key is separate
    from `Lit.api_key` so AI access can be revoked without breaking environment sync.
  - `GET /api/v1/ai/pending`, `POST /api/v1/ai/suggestions`, `POST /api/v1/ai/refresh_keys`.
- Tags on localization keys, set by the AI API, with a searchable multiselect filter
  on the localization key lists and on the AI tab. The filter offers only tags present
  in the current tab.

### Fixed
- The "batch touch" link now forwards the whole active filter. It previously rebuilt
  its scope from `key`/`key_prefix` only, so with any other filter active it marked far
  more keys for synchronization than the confirm dialog claimed.
- The test suite now runs on Ruby 3.2 / Rails 7.2: relaxed the `pry-byebug` pin (pry 0.13
  calls `Object#=~`, removed in Ruby 3.2), `mocha/setup` -> `mocha/minitest`, the renamed
  `MiniTest` constant, and `fixture_path=` -> `fixture_paths=`. The dummy app called
  `Lit.init` at initializer top level, which Rails 7 forbids.

## [WIP]
- Efforts to use Vanilla JS and remove jQuery [WIP]
- Fix for `Undefined method 'id' for False class` error in view partial [WIP]

## [1.1.6] - 2022-03-28
### Fixed
- When running Lit on Rails 6.1 defaults could sometimes be overwritten [@pnikrat](https://github.com/pnikrat)

## [1.1.5] - 2021-12-23
### Added
- Lit is now compatible with Zeitwerk and classic loader [@mlitwiniuk](https://github.com/mlitwiniuk)
- When using Cloud translations, support V2 `google-cloud-translate` gem [@pnikrat](https://github.com/pnikrat)
- Proper Rails 6.1 support. Fixes new Rails translate logic not saving defaults in Lit [@pnikrat](https://github.com/pnikrat)
- Add screenshots to README [@mlitwiniuk](https://github.com/mlitwiniuk)
- Proper CHANGELOG [@pnikrat](https://github.com/pnikrat)

### Changed
- Lit now uses Ruby 2.7.4 [@pnikrat](https://github.com/pnikrat)

### Fixed
- When cloud translating strings with newline characters they are now properly preserved when returned from cloud translation provider [@pnikrat](https://github.com/pnikrat)

## [1.1.4] - 2021-04-27
### Fixed / Changed
- Move initializer template to `erb`. This may fix some errors on Lit installation [@mlitwiniuk](https://github.com/mlitwiniuk)

## [1.1.2] - 2021-04-26
### Added
- Ruby 3.0 compatibility [@mlitwiniuk](https://github.com/mlitwiniuk)
- Option to batch-touch localizations. This marks them for synchronization again [@mlitwiniuk](https://github.com/mlitwiniuk)
- Copy localization key to clipboard from Lit dashboard [@mlitwiniuk](https://github.com/mlitwiniuk)

### Removed
- Rails 5.1 support. Use 5.2 or higher

## [1.1.1] - 2021-03-08
### Added
- Performance improvements: caching translation values in memory [@mlitwiniuk](https://github.com/mlitwiniuk)
- More thread-safety: added middleware to clear Thread.current value after request is done [@mlitwiniuk](https://github.com/mlitwiniuk)

### Fixed
- Fixes problem with duplication on synchronization - when synchronizing with remote record duplication was not properly checked [@mlitwiniuk](https://github.com/mlitwiniuk)

## [1.1.0] - 2020-11-03
### Added
- Lit startup performance improvements - memoize cache keys during startup [@vincentvanbush](https://github.com/vincentvanbush)
- Cache consecutive calls to same localization key + other performance improvements [@mlitwiniuk](https://github.com/mlitwiniuk)
- Support WillPaginate if present in project
- Extra includes to avoid unnecessary queries in API controllers
- Support for Rails 6 and I18n 1.6 [@mlitwiniuk](https://github.com/mlitwiniuk) & [@vincentvanbush](https://github.com/vincentvanbush)
- Support Redis 5.0 [@usiegj00](https://github.com/usiegj00)
- Lit now properly returns hash/subtree of translations when asked for non-leaf node [@pnikrat](https://github.com/pnikrat)

### Changed
- Use local Bootstrap instead of CDN [@sweetyclem](https://github.com/sweetyclem/)
- Generated initializer now respects `ignored_keys` setting [@mlitwiniuk](https://github.com/mlitwiniuk)

### Fixed
- Remote interactor service fixes [@usiegj00](https://github.com/usiegj00)
- Import will now update only default value when `raw` option is true [@AliSepehri](https://github.com/AliSepehri)
- Fix Rails constant reference and some README improvements [@texpert](https://github.com/texpert)

## [1.0.2] - 2019-06-27
### Fixed
- Fix problem with code reloading [@Bonias](https://github.com/Bonias)
- Fix fallback keys firing unnecessary queries [@vincentvanbush](https://github.com/vincentvanbush)

### Changed
- Use Emoji flags instead of famfamfam [@zsawala](https://github.com/zsawala)

## [1.0.1] - 2019-01-10
### Fixed
- Fix missing trailing nil values in imported arrays [@vincentvanbush](https://github.com/vincentvanbush)
- Fix array element nil value handling in cloud translation [@vincentvanbush](https://github.com/vincentvanbush)

## [1.0] - 2019-01-09
### Added
- Cloud Translations feature [@vincentvanbush](https://github.com/vincentvanbush)
- Localization key/Locale unique index [@vincentvanbush](https://github.com/vincentvanbush)
- Add INCLUDE_HITS_COUNT option to CSV export [@vincentvanbush](https://github.com/vincentvanbush)

### Changed
- Introduce a list of keys to ignore for auto-humanize [@mlitwiniuk](https://github.com/mlitwiniuk)
- Storing localizations even after rollback [@mlitwiniuk](https://github.com/mlitwiniuk)
- Gemspec updates [@josh-m-sharpe](https://github.com/josh-m-sharpe)
- Test suite updates and cleanup [@josh-m-sharpe](https://github.com/josh-m-sharpe) & [@vincentvanbush](https://github.com/vincentvanbush)

### Fixed
- is_changed not being set correctly on UI edits [@vincentvanbush](https://github.com/vincentvanbush)

## [0.4.0-alpha] - 2018-11-12
### Added
- Add Redis URL to config [@Silex](https://github.com/Silex)
- Rails 5.2 support [@vincentvanbush](https://github.com/vincentvanbush)
- Show encountered and not yet translated localization keys [@szsoppa](https://github.com/szsoppa)
- Synchronize deleted localizations [@szsoppa](https://github.com/szsoppa)
- CSV export [@vincentvanbush](https://github.com/vincentvanbush)
- Add Arel::Nodes.build_quoted when searching by params[:key] [@mlitwiniuk](https://github.com/mlitwiniuk)

### Changed
- Various improvements [@Silex](https://github.com/Silex)
- Code refactoring (rubocop) [@szsoppa](https://github.com/szsoppa)

### Fixed
- Properly scope Lit inner translations [@Silex](https://github.com/Silex)
- Proper pluralization support [@Silex](https://github.com/Silex)
- Prevent from overwriting DB with nil defaults when redis gets cleared [@vincentvanbush](https://github.com/vincentvanbush)
- Fix :default option not overriding stored nil value [@vincentvanbush](https://github.com/vincentvanbush)

## [0.3.3] - 2018-04-05
### Added
- Inline editing [@mlitwiniuk](https://github.com/mlitwiniuk)
- Support Rails 4.2-5.0 and Ruby 2.3-2.4 [@mlitwiniuk](https://github.com/mlitwiniuk) & [@zhisme](https://github.com/zhisme)
- Support Rails 5.1 [@mlitwiniuk](https://github.com/mlitwiniuk)

### Changed
- Sync only UI modified keys [@vincentvanbush](https://github.com/vincentvanbush)
- Asynchronous loading of translations synchronized via API [@vincentvanbush](https://github.com/vincentvanbush)
- Better caching [@mlitwiniuk](https://github.com/mlitwiniuk)
- Streamline installation process (no migration copying) [@mlitwiniuk](https://github.com/mlitwiniuk)
- Loosen I18n dependency

### Fixed
- Fix/yaml translations overwriting [@vincentvanbush](https://github.com/vincentvanbush)

### Removed
- Support for Rails &lt;4.2

## [0.2.6] - 2016-05-12
### Added
- Infer underscore key names from space-separated search queries [@vincentvanbush](https://github.com/vincentvanbush)
- Various optimizations

## [0.2.5] - 2015-11-19
### Added
- Ignoring key prefixes [@mlitwiniuk](https://github.com/mlitwiniuk)

### Changed
- Various refactoring and optimizations [@Bonias](https://github.com/Bonias) & [@mlitwiniuk](https://github.com/mlitwiniuk)
- Move Lit panel to Bootstrap 3 [@mlitwiniuk](https://github.com/mlitwiniuk)

### Fixed
- Only save translations for locales defined in available_locales [@stephanvane](https://github.com/stephanvane)

## [0.2.1] - 2013-10-18
### Changed
- Use Arel to create SQL searches [@Bonias](https://github.com/Bonias)

### Fixed
- Fix array translations updating [@Bonias](https://github.com/Bonias)

## [0.2.0] - 2013-10-11
### Added
- jQuery TE as WYSIWYG editor [@mlitwiniuk](https://github.com/mlitwiniuk)
- Sorting of localization keys [@Bonias](https://github.com/Bonias)

### Changed
- Updates to License
- Initial loading improvements [@Bonias](https://github.com/Bonias)
- Performance improvements [@Bonias](https://github.com/Bonias)
- Pure I18n compatibility [@Bonias](https://github.com/Bonias)

### Fixed
- Submit button breaking when translation missing message appears [@Bonias](https://github.com/Bonias)

### Removed
- Support for default Proc values [@mlitwiniuk](https://github.com/mlitwiniuk)

## [0.1.0] - 2013-09-25
### Added
- Support nil values
- Install generator
- API, groundwork for syncing keys between environments
- Syncing keys between envs

### Changed
- Improvements to Array support
- Updates to Readme

## [0.0.4.3] - 2013-09-18
### Added
- Export tasks
- Setting default text
- Arrays support
- Hit counters for translation keys
- Locale can be hidden
- Translation fallbacks

### Changed
- Refactoring and cleanup

## 0.0.4 - 2013-01-15
- Prefixing Redis storage keys
- Rails 4 compatibility
- Further development

## 0.0.3.1 - 2012-12-31
- Updates to gemspec and readme. Added License

## 0.0.3 - 2012-12-31
- Initial release

[Unreleased]: https://github.com/prograils/lit/compare/1.1.6...HEAD
[1.1.6]: https://github.com/prograils/lit/compare/1.1.5...1.1.6
[1.1.5]: https://github.com/prograils/lit/compare/573b2f4272976a78951953a8ee37f2a533e181a1...1.1.5
[1.1.4]: https://github.com/prograils/lit/compare/4cedfd00e29b85e848502dd82d479cff0777322b...573b2f4272976a78951953a8ee37f2a533e181a1
[1.1.2]: https://github.com/prograils/lit/compare/1.1.1...4cedfd00e29b85e848502dd82d479cff0777322b
[1.1.1]: https://github.com/prograils/lit/compare/1.1.0...1.1.1
[1.1.0]: https://github.com/prograils/lit/compare/1.0.2...1.1.0
[1.0.2]: https://github.com/prograils/lit/compare/1.0.1...1.0.2
[1.0.1]: https://github.com/prograils/lit/compare/1.0...1.0.1
[1.0]: https://github.com/prograils/lit/compare/0.4.0%2Dalpha...1.0
[0.4.0-alpha]: https://github.com/prograils/lit/compare/v0.3.3...0.4.0%2Dalpha
[0.3.3]: https://github.com/prograils/lit/compare/v0.2.6...v0.3.3
[0.2.6]: https://github.com/prograils/lit/compare/v0.2.5...v0.2.6
[0.2.5]: https://github.com/prograils/lit/compare/v0.2.1...v0.2.5
[0.2.1]: https://github.com/prograils/lit/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/prograils/lit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/prograils/lit/compare/v0.0.4.3...v0.1.0
[0.0.4.3]: https://github.com/prograils/lit/compare/98b331975dfad4b4a01a290a9d27abdfa9db17f0...v0.0.4.3

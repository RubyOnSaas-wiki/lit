# AI translation suggestions, tags and tag filter for Lit

Date: 2026-09-01
Repos: `lit` (gem, primary) and `elvium` (host app, small config changes)
Status: design approved, ready for implementation planning

## 1. Purpose

Let an AI agent push proposed translations into Lit over an authorized HTTP API, and let a
human review those proposals in a dedicated **AI translated** tab before any of them affect
the application. Add a tag concept (feature names recorded when a key was introduced) with a
searchable multiselect filter.

Until a proposal is accepted, nothing changes: the Translate! tab, the export, the
prod/pre-prod synchronization and the running application all behave exactly as they do today.

## 2. Decisions

| Decision | Choice | Why |
|---|---|---|
| Where proposals live | New `lit_ai_suggestions` table | Keeps `IncommingLocalization` (which is bound to `Source` and nested under `/sources/:id/`) untouched, and keeps proposal writes off `lit_localizations`, whose `updated_at` drives `Localization.after` and therefore the prod/pre-prod sync |
| Tags | `lit_tags` + join table, attached to `LocalizationKey` | Survive acceptance; portable across databases; tag name is a first-class value for autocomplete |
| Who sets tags | Only the API | No manual tag CRUD in the UI |
| Auth | Separate `Lit.ai_api_key` | Rotate or revoke AI access without breaking environment sync, which uses `Lit.api_key` |
| Unknown keys | Rejected, reported in the response | Keys are created by the app calling `I18n.t`; rejecting protects against typos |
| Duplicate proposal | Upsert on (key, locale) | Retry-safe; the tab does not fill with duplicates |
| Human edit meanwhile | Proposal stays, with a warning badge | Nothing disappears without a human decision |
| Target environment | pre-prod (and other non-production envs) | `elvium/config/routes.rb:43-45` mounts the engine outside `authenticated :admin_user` only when `Rails.env.production?` is false. Pre-prod is already the translation authoring host; production pulls from it (`elvium/config/initializers/lit.rb:3-4`) |
| Accept all | Background job, no polling | Thousands of rows cannot be accepted inside one request |

## 3. Data model

### 3.1 `lit_ai_suggestions`

Migration `lit/db/migrate/<ts>_lit_create_lit_ai_suggestions.rb`, styled like the existing
lit migrations (`ActiveRecord::Migration[4.2]`, `t.integer` foreign keys to match lit's
`serial` primary keys, indexes declared with `add_index` inside the same migration).

| column | type | purpose |
|---|---|---|
| `localization_key_id` | integer | FK |
| `locale_id` | integer | FK |
| `suggested_value` | text | the proposal; `serialize` on the model, matching `Localization#translated_value`, so array-valued keys such as `date.abbr_day_names` work |
| `base_value` | text | `serialize`; snapshot of the translation at the moment the proposal was created |
| `provider` | string | e.g. `claude-opus-5`, shown on the tab |
| `is_edited` | boolean, default false | a human edited the proposal before accepting |
| timestamps | | |

Unique index on `[localization_key_id, locale_id]`; plain index on `locale_id`.

`base_value` exists so staleness is detected by comparing values, never timestamps:
`LocalizationKeysController#batch_touch` runs `update_all updated_at: Time.current` across
whole search results, so an `updated_at` comparison would raise false warnings.

Model `Lit::AiSuggestion < Lit::Base`:

- `belongs_to :localization_key`, `belongs_to :locale`
- `scope :stale` / `#stale?` -> `base_value != current_value`
- `#current_value` -> `Lit.init.cache["#{locale.locale}.#{localization_key.localization_key}"]`
- `#accept` (see 5.3)

`Lit::LocalizationKey` gains `has_many :ai_suggestions, dependent: :destroy`, and
`Lit::Locale` likewise, so destroying a key or locale does not orphan proposals.
`LocalizationKey#soft_destroy` does **not** touch proposals; the tab excludes keys with
`is_deleted = true` via the existing `active` scope.

### 3.2 Tags

Migration `<ts>_lit_create_lit_tags.rb`:

- `lit_tags`: `name` (string, not null), unique index on `name`, timestamps
- `lit_localization_key_tags`: `localization_key_id`, `tag_id`, timestamps, unique index on the pair

Use an explicit join **model** with `has_many :through`, not HABTM. Rails derives the HABTM
join table name as `lit_localization_keys_tags` (plural `keys`) from the two table names, which
would raise `PG::UndefinedTable` on every tag read; a join model states its table name once and
removes the footgun. It is also what section 6.3 queries directly.

```ruby
# app/models/lit/localization_key_tag.rb
module Lit
  class LocalizationKeyTag < Lit::Base
    self.table_name = 'lit_localization_key_tags'
    belongs_to :localization_key
    belongs_to :tag
  end
end

# app/models/lit/localization_key.rb
has_many :localization_key_tags, dependent: :delete_all
has_many :tags, through: :localization_key_tags

# app/models/lit/tag.rb
has_many :localization_key_tags, dependent: :delete_all
has_many :localization_keys, through: :localization_key_tags
```

`Lit::Tag` normalizes `name` on write with `strip.downcase`; creation from the API uses
`find_or_create_by` with a rescue on `ActiveRecord::RecordNotUnique`, mirroring
`LocalizationKey.find_or_create_by_localization_key`.

### 3.3 Migration delivery

New migrations live only in `lit/db/migrate/`. The `lit.migrations.append` initializer
(`lit/lib/lit/engine.rb:20-24`) adds the engine's migration path to the host, which is how
lit's 2018 and 2025 migrations already reach elvium without being copied.

**But** elvium builds databases from the committed schema dump, not from migrations:
`.github/workflows/ci.yml:128` runs `rake db:schema:load` and `spec/rails_helper.rb:69` calls
`maintain_test_schema!`. So the elvium task list must include: bump the `lit` git ref, run
`bin/rails db:migrate`, and **commit the regenerated `db/schema.rb`** containing the three new
tables. Without it, CI either fails with `PendingMigrationError` or with
`relation "lit_ai_suggestions" does not exist`.

Elvium is Rails 7.2.2.1 and uses `online_migrations` with `start_after = 20220616131835`;
keeping index creation inside `create_table` keeps the new-table exemption applicable.

## 4. HTTP API

New `Lit::Api::V1::Ai::BaseController`, authenticating with
`authenticate_or_request_with_http_token` against `Lit.ai_api_key`. It **fails closed**: a
blank `Lit.ai_api_key` rejects every request rather than authorizing anyone. The sync key
`Lit.api_key` must not be accepted.

New module attributes in `lit/lib/lit.rb`: `ai_api_enabled`, `ai_api_key`. Routes are drawn
inside `if Lit.ai_api_enabled`, mirroring the existing `if Lit.api_enabled` block; host
initializers run before the routes reloader, so this is safe.

Header: `Authorization: Token token="..."`.

### 4.1 `GET /lit/api/v1/ai/pending`

Params: `locale` (required), `source_locale` (default `en`), `tags[]`, `limit` (default 100,
max 500), `page`.

The scope must treat a **missing** localization row as untranslated. `Lit::Localization` rows
are created lazily per (locale, key) on first lookup; `clone_localizations` has no callers in
the gem, so most keys have no row for most locales. An INNER JOIN would hide the majority of
the backlog.

```ruby
translated_ids = Lit::Localization.where(locale_id: locale.id, is_changed: true)
                                  .select(:localization_key_id)
scope = Lit::LocalizationKey.active.where.not(id: translated_ids)
```

Source-locale context is read from `Lit.init.cache["#{source_locale}.#{key}"]`, not from a
`Localization` row, for the same reason. Keys with no source value are still returned, with
`source_value: null`, so the AI can decide what to do.

Response per item: `key`, `locale`, `source_value`, `current_value`, `tags`,
`existing_suggestion` (value or null).

### 4.2 `POST /lit/api/v1/ai/suggestions`

```json
{ "provider": "claude-opus-5",
  "suggestions": [
    { "key": "hr.tree.title", "locale": "sv", "value": "Organisationsträd",
      "tags": ["hr-tree", "dev-958"] }
  ] }
```

- Upsert on `(localization_key_id, locale_id)`; on conflict, overwrite `suggested_value`,
  refresh `base_value` and `provider`, and union the tags.
- **Exception:** a proposal with `is_edited = true` is not overwritten. A human has already
  worked on it, and a re-push would silently discard that work. The item is reported in a
  `skipped` array with `reason: "kept_human_edit"`; its tags are still unioned. To replace it,
  reject the proposal in the UI first.
- `base_value` is set from `Lit.init.cache[...]` at write time.
- Unknown key -> `reason: "unknown_key"`; unknown locale -> `reason: "unknown_locale"`.
  Nothing is created for a rejected item.
- Tags attach to the **key**, so they survive acceptance.
- Batch cap: 500 items per request; a larger body is rejected with `413`.
- Partial success is intentional: valid items are written, invalid ones are reported.

Response: `{ "created": 12, "updated": 3, "skipped": [...], "rejected": [{"key": "...", "locale": "sv", "reason": "unknown_key"}] }`

### 4.3 `POST /lit/api/v1/ai/refresh_keys`

Enqueues `Lit::RefreshKeysJob`, which calls `I18n.backend.init_translations_with_caching` --
the same scan elvium's `LitInitializerJob` runs weekly (`config/schedule.yml`,
`synchronize_new_strings_in_lit`, Sundays 02:05). It imports keys newly added to
`config/locales/*.yml` and never overwrites existing values.

Returns `202 {"status": "enqueued"}`, or `200 {"status": "already_running"}` when the guard is
already held. The guard is a `Rails.cache` key claimed by the **controller** with
`write(key, true, unless_exist: true, expires_in: 30.minutes)` -- an atomic claim, so two
simultaneous requests cannot both enqueue -- and released by the job in an `ensure` block. The
TTL bounds a crashed job so the endpoint cannot deadlock.

This is step 0 of the AI loop: *refresh -> pending -> suggestions*.

### 4.4 Rate limiting (host side)

Elvium's `Rack::Attack` throttles every non-`/assets` path at 20 requests / 10 seconds per IP,
which would 429 the AI client almost immediately. `config/initializers/rack_attack.rb` must
exclude `%r{\A/lit/api/v1/ai/}` from the global per-IP throttle and give it its own
token-keyed throttle (falling back to per-IP when no token is present, so the key stays
brute-force resistant), plus
`Rack::Attack.throttled_response_retry_after_header = true`.

## 5. The "AI translated" tab

### 5.1 Placement

New item in `app/views/layouts/lit/_navigation.html.erb` with a pending-count badge.
`Lit::AiSuggestionsController < Lit::ApplicationController`, so it inherits
`Lit.authentication_function` (admin session) exactly like every other Lit UI controller.

Routes:

```ruby
resources :ai_suggestions, only: %i[index update destroy] do
  member { post :accept }
  collection { post :accept_all; delete :reject_all }
end
```

### 5.2 The list

Paginated with Kaminari, like `localization_keys/index.html.erb` (**not** like
`incomming_localizations/index.html.erb`, which is unpaginated). Grouped by key, one row per
locale:

`flag / locale | current value | proposal (inline editable) | accept | edit | reject`

The current value is read from `Lit.init.cache["#{locale}.#{key}"]` -- the same source
`_localizations_list.html.erb` uses -- so it is always live, and `Lit::Cache#[]` already
returns `nil` for a key with no row. A `stale?` proposal (base_value differs from the current
value) shows a "changed manually since proposed" badge.

A permanent explanatory block sits at the top of the tab:

> **AI translation proposals.** Nothing here is live yet -- until you accept, the application
> uses the "Current value" column. "Proposal" is what the AI suggests; you can edit it before
> accepting. **Accept** writes the value into the translations, marks it ready for
> synchronization, and removes the proposal. **Reject** deletes the proposal and changes
> nothing. Tags are the names of the features a key was introduced for.

### 5.3 Accept

Specified literally, because the `Localization` row usually does not exist yet and
`after_commit :update_cache` is registered `on: :update` only:

```ruby
def accept
  localization = localization_key.localizations.find_or_initialize_by(locale_id: locale_id)
  localization.translated_value = suggested_value
  localization.is_changed = true
  localization.save!
  Lit.init.cache.update_cache(localization.full_key, localization.translation)
  destroy
end
```

`belongs_to :localization_key, touch: true` then fires the key's `after_commit :check_completed`.
`is_changed = true` is what puts the value into `Lit::Export` and into `Localization.after`,
which the prod/pre-prod sync reads.

### 5.4 Accept all / reject / edit

- **Accept all** enqueues `Lit::AcceptAiSuggestionsJob` with the current filter params, then
  redirects immediately with a flash naming the count ("accepting N proposals in the
  background"). The job iterates `in_batches(of: 200)` with one transaction per batch. No
  polling: the user refreshes to see progress. The confirm dialog states the filtered count.
- **Reject** destroys the proposal.
- **Reject all** destroys everything in the current filter scope.
- **Edit** is an inline textarea with a remote PATCH, reusing the pattern in
  `localizations/edit.js.erb` and `update.js.erb`; it sets `is_edited` and shows a badge.
  Acceptance uses the edited value.

## 6. Tags and the filter

### 6.1 Permitting the parameter

`params.permit` with a flat list silently discards array values, so the filter would look
active and do nothing:

```ruby
def find_localization_scope
  @search_options =
    if params.respond_to?(:permit)
      params.permit(:key, :key_prefix, :order, :tags, tags: [])
    else
      params.slice(*valid_keys)
    end
  @scope = LocalizationKey.distinct.active.preload(localizations: :locale).search(@search_options)
  @tag_options_scope = LocalizationKey.distinct.active.search(@search_options.except(:tags))
end

def valid_keys
  %w[key key_prefix order tags]
end
```

`not_translated`, `visited_again` and `starred` narrow `@scope` after the `before_action`;
`@tag_options_scope` must be narrowed the same way in each, and in the AI tab.

### 6.2 Filtering

Added to `LocalizationKeySearchQuery#perform`, OR semantics across selected tags:

```ruby
def search_tags
  names = Array(@params[:tags]).map(&:to_s).map(&:strip).reject(&:blank?)
  return if names.empty?
  @scope = @scope.joins(:tags).where(lit_tags: { name: names })
end
```

The controller already applies `.distinct`, so the join does not duplicate rows.

### 6.3 The active-tag option list

Two things are mandatory here. `@scope` always carries `distinct` **and** an ORDER BY
(`LocalizationKeySearchQuery#order_data` applies one unconditionally), and
`PredicateBuilder::RelationHandler` inlines the subquery AST verbatim, so passing `@scope`
into a subquery raises
`PG::InvalidColumnReference: for SELECT DISTINCT, ORDER BY expressions must appear in select list`
on Postgres -- which is what both elvium and the gem's dummy app run. And the options must be
computed from the scope **without** the tag filter, or the dropdown narrows itself and OR
semantics become unusable.

```ruby
def tag_filter_options
  tag_ids = Lit::LocalizationKeyTag
              .where(localization_key_id: @tag_options_scope.reorder(nil)
                                                            .unscope(:limit, :offset)
                                                            .select(:id))
              .distinct.select(:tag_id)
  Lit::Tag.where(id: tag_ids)
          .or(Lit::Tag.where(name: Array(@search_options[:tags])))
          .order(:name)
end
helper_method :tag_filter_options
```

`reorder(nil)` mirrors the existing `@prefixes` line in `get_localization_keys`. OR-ing in the
current selection guarantees select2 can always re-offer what is selected.

### 6.4 batch touch

`_localizations_list.html.erb:2` hardcodes `key` and `key_prefix`, so with a tag filter active
the link would touch every key matching key/key_prefix while the confirm dialog claims it acts
on the filtered results -- a mass, irreversible marking for synchronization. The link must
forward `@search_options`, and the confirm text should state the filtered count.

### 6.5 Widget

select2 4.x vendored into `app/assets/javascripts/lit/backend/`, CSS added to the
`lit/application.css` manifest. Lit runs on sprockets with jQuery and has no npm.

## 7. Host (elvium) changes

1. `config/initializers/lit.rb`, at top level next to the existing api settings (lines 35/38):
   ```ruby
   Lit.ai_api_enabled = true
   Lit.ai_api_key = ENV.fetch('LIT_AI_API_KEY')
   ```
   Both are required. Without the flag the routes are never drawn and every endpoint 404s with
   nothing in the logs to explain it. Do not infer the flag from the key inside `Lit.init` --
   those defaults sit inside `if loader.nil? && @@table_exists` and are skipped on a host whose
   tables do not exist yet. Unlike the existing `Lit.api_key`, the new key comes from ENV.
2. `config/initializers/rack_attack.rb`: exempt `/lit/api/v1/ai/` from the global per-IP
   throttle, add a token-keyed throttle, enable the `Retry-After` header.
3. Bump the `lit` git ref in `Gemfile` / `Gemfile.lock`, run `bin/rails db:migrate`, commit the
   regenerated `db/schema.rb`.
4. Update `STRUCTURE.md` per elvium's `CLAUDE.md`.

Deployment targets pre-prod and other non-production environments. In production the engine is
mounted inside `authenticated :admin_user` (`config/routes.rb:44-45`), so the token-only
endpoints are route-absent there by design; production receives accepted translations through
the existing sync.

## 8. Testing

Matching the existing layout in the gem:

- `test/unit/lit/ai_suggestion_test.rb` -- upsert; accept when the `Localization` row does not
  exist; accept when it does; array-valued keys; `stale?`; cache updated after accept.
- `test/unit/lit/tag_test.rb` -- normalization, uniqueness race, and a real association
  round-trip (`Lit::Tag.joins(:localization_keys).count`) so a wrong join table fails in unit
  tests rather than in the UI.
- `test/functional/lit/api/v1/ai/suggestions_controller_test.rb` -- no token; wrong token;
  **the sync key `Lit.api_key` must be rejected**; blank `Lit.ai_api_key` rejects everything;
  upsert; unknown key and unknown locale reported without being created; batch cap.
- `test/functional/lit/api/v1/ai/pending_controller_test.rb` -- a key with no `Localization`
  row for the target locale **is** returned; a translated key is not.
- `test/functional/lit/ai_suggestions_controller_test.rb` -- accept, reject, edit, accept_all
  enqueues the job with the filter, pagination.
- `test/functional/lit/localization_keys_controller_test.rb` -- tag filter asserts the
  **filtered count**, not just a 200 (a status-only assertion would have passed while the param
  was silently dropped); one request per entry in `LocalizationKey.order_options` combined with
  `tags[]`, asserting 200, because the DISTINCT/ORDER BY bug is invisible on SQLite;
  `batch_touch` with a tag filter leaves an untagged key untouched.
- `test/dummy/config/initializers/lit.rb` gains `Lit.ai_api_enabled = true` and
  `Lit.ai_api_key`.

## 9. Out of scope

Manual tag CRUD in the UI; automatic key creation from the API; proposal history after
acceptance or rejection; multiple competing proposals for one key and locale; exposing the AI
endpoints on production.

## 10. Suggested implementation order

The two halves are independent and can ship separately:

1. **Tags and filter** (gem): migrations, `Lit::Tag` and `Lit::LocalizationKeyTag`, `search_tags`,
   the permit fix, `tag_filter_options`, the batch-touch fix, select2. Shippable on its own --
   with no API yet, the tag list is simply empty.
2. **AI suggestions** (gem): `lit_ai_suggestions`, `Lit::AiSuggestion`, the three API endpoints,
   `Lit::RefreshKeysJob`, the tab, `Lit::AcceptAiSuggestionsJob`.
3. **Host** (elvium): initializer, `Rack::Attack`, gem ref bump, `db/schema.rb`, `STRUCTURE.md`.

## 11. Audit trail

This design was revised after an adversarial review (six independent lenses reading the real
`lit` and `elvium` sources, every finding then checked by a refute-by-default verifier).
Corrected before approval: the missing `Lit.ai_api_enabled` host setting; the elvium
`db/schema.rb` requirement; the assumption that a `Localization` row exists for every
(key, locale); the Postgres `SELECT DISTINCT` / `ORDER BY` failure in the active-tag query;
`tags[]` being dropped by `params.permit`; the HABTM join table name; the self-narrowing tag
dropdown; `batch_touch` ignoring the tag filter; synchronous `accept_all` and the unpaginated
tab; and the `Rack::Attack` throttle.

## 12. Implementation notes (deviations from the design above)

Recorded while implementing, so the document matches the code:

1. **`ActiveRecord::Base`, not `Lit::Base`.** `Lit::AiSuggestion`, `Lit::Tag` and
   `Lit::LocalizationKeyTag` inherit `ActiveRecord::Base`, matching
   `Lit::IncommingLocalization` -- the closest analogue and also a staging table.
   `Lit::Base` re-inserts rolled-back rows (`app/models/lit/base.rb#do_retry`), which is
   the wrong behaviour inside the bulk API write path and the batched accept-all
   transaction.
2. **select2 from a CDN, not vendored.** `layouts/lit/application.html.erb` already loads
   Bootstrap 3 and Font Awesome from a CDN; select2 4.0.13 is loaded the same way instead
   of committing a minified vendor blob to the gem.
3. **Shared code extracted.** Tag-filter plumbing lives in the `Lit::TagFilterable`
   concern (`app/controllers/lit/tag_filterable.rb`), used by both
   `LocalizationKeysController` and `AiSuggestionsController`. Suggestion filtering lives
   in `AiSuggestionSearchQuery` (`app/queries/`), shared by the tab and
   `Lit::AcceptAiSuggestionsJob` so "accept all" acts on exactly what was on screen.
4. **The join table keeps a primary key.** `has_many :through` needs a join model, so
   `lit_localization_key_tags` is an ordinary table rather than `id: false`.
5. **`ENV.fetch('LIT_AI_API_KEY', nil)`**, not a bare `ENV.fetch`. A missing variable must
   not break boot on a developer machine; the controller already fails closed and returns
   401 when the key is blank.

### Test-environment repairs

The gem's suite could not run at all on Ruby 3.2 / Rails 7.2 before this work. Fixed as
part of it, all pre-existing and unrelated to the feature:

- `lit.gemspec`: `pry-byebug '~> 3.9.0'` pinned pry 0.13, which calls `Object#=~`, removed
  in Ruby 3.2. Relaxed to `>= 3.9`.
- `test/test_helper.rb`: `mocha/setup` (gone in mocha 2), the `MiniTest` constant
  (renamed in minitest 5.19, still referenced by minitest-vcr), and
  `fixture_path=` (`fixture_paths=` since Rails 7.1).
- `test/dummy/config/initializers/lit.rb`: `Lit.init` ran at initializer top level, which
  Rails 7 forbids (autoloading during initialization). Moved into `after_initialize`,
  matching what elvium already does.
- `test/dummy/config/database.yml` created from the sample (untracked).

### Still outstanding

`db/schema.rb` in elvium cannot be regenerated yet: elvium resolves `lit` from the
`RubyOnSaas-wiki/lit` git ref, so the new migrations only reach it after these gem changes
are pushed and the ref is bumped. Sequence: push lit -> bump `Gemfile`/`Gemfile.lock` ->
`bin/rails db:migrate` -> commit `db/schema.rb`.

require_dependency 'lit/api/v1/ai/base_controller'

module Lit
  module Api
    module V1
      module Ai
        class SuggestionsController < BaseController
          MAX_BATCH_SIZE = 500
          MAX_PAGE_SIZE = 500
          DEFAULT_PAGE_SIZE = 100

          # GET /api/v1/ai/pending
          def pending
            locale = find_locale(params[:locale])
            return render_error('unknown or missing locale') if locale.nil?

            source_locale = find_locale(params[:source_locale].presence || 'en')
            keys = pending_scope(locale).limit(page_size).offset(page_offset).to_a
            suggestions = Lit::AiSuggestion.where(locale_id: locale.id,
                                                  localization_key_id: keys.map(&:id))
                                           .index_by(&:localization_key_id)

            render json: {
              locale: locale.locale,
              source_locale: source_locale&.locale,
              count: keys.size,
              keys: keys.map { |key| pending_entry(key, locale, source_locale, suggestions[key.id]) }
            }
          end

          # POST /api/v1/ai/suggestions
          def create
            items = Array(params[:suggestions])
            return head(:payload_too_large) if items.size > MAX_BATCH_SIZE

            result = { created: 0, updated: 0, skipped: [], rejected: [] }
            items.each { |item| process_item(item, result) }
            render json: result
          end

          # POST /api/v1/ai/refresh_keys
          def refresh_keys
            if Lit::RefreshKeysJob.claim_guard
              Lit::RefreshKeysJob.perform_later
              render json: { status: 'enqueued' }, status: :accepted
            else
              render json: { status: 'already_running' }
            end
          end

          private

          def find_locale(value)
            return if value.blank?
            Lit::Locale.find_by(locale: value.to_s)
          end

          def render_error(message, status: :bad_request)
            render json: { error: message }, status: status
          end

          # A key counts as untranslated when it has no localization row for the
          # locale at all, which is the common case: rows are created lazily,
          # one (locale, key) pair at a time.
          def pending_scope(locale)
            translated_ids = Lit::Localization.where(locale_id: locale.id, is_changed: true)
                                              .select(:localization_key_id)
            scope = Lit::LocalizationKey.active.where.not(id: translated_ids)
            scope = scope.joins(:tags).where(Lit::Tag.table_name => { name: tag_names }).distinct if tag_names.any?
            scope.order(:localization_key)
          end

          def tag_names
            @tag_names ||=
              Array(params[:tags]).map { |name| Lit::Tag.normalize(name) }.reject(&:blank?)
          end

          def page_size
            requested = params[:limit].to_i
            requested = DEFAULT_PAGE_SIZE if requested <= 0
            [requested, MAX_PAGE_SIZE].min
          end

          def page_offset
            page = params[:page].to_i
            page = 1 if page <= 0
            (page - 1) * page_size
          end

          def pending_entry(key, locale, source_locale, suggestion)
            { key: key.localization_key,
              locale: locale.locale,
              source_value: source_locale && cached_value(source_locale, key),
              current_value: cached_value(locale, key),
              tags: key.tags.map(&:name),
              existing_suggestion: suggestion&.suggested_value }
          end

          def cached_value(locale, key)
            Lit.init.cache["#{locale.locale}.#{key.localization_key}"]
          end

          def process_item(item, result)
            item = permitted_item(item)
            key = Lit::LocalizationKey.find_by(localization_key: item[:key].to_s)
            return reject(result, item, 'unknown_key') if key.nil?

            locale = find_locale(item[:locale])
            return reject(result, item, 'unknown_locale') if locale.nil?

            status, _suggestion = Lit::AiSuggestion.propose(
              localization_key: key, locale: locale,
              value: item[:value], provider: params[:provider]
            )
            attach_tags(key, item[:tags])

            case status
            when :created then result[:created] += 1
            when :updated then result[:updated] += 1
            else result[:skipped] << entry(item, status.to_s)
            end
          end

          def permitted_item(item)
            return item.permit(:key, :locale, :value, value: [], tags: []) if item.respond_to?(:permit)
            item
          end

          def attach_tags(key, names)
            Array(names).each do |name|
              tag = Lit::Tag.find_or_create_normalized(name)
              next if tag.nil?
              Lit::LocalizationKeyTag.find_or_create_by(localization_key_id: key.id, tag_id: tag.id)
            rescue ActiveRecord::RecordNotUnique
              next
            end
          end

          def reject(result, item, reason)
            result[:rejected] << entry(item, reason)
          end

          def entry(item, reason)
            { key: item[:key], locale: item[:locale], reason: reason }
          end
        end
      end
    end
  end
end

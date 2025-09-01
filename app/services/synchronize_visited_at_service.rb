class SynchronizeVisitedAtService
  def call
    hits_counter = get_hits_counter
    return unless hits_counter
    
    hits_tracker_keys = get_hits_tracker_keys(hits_counter)
    
    hits_tracker_keys.each do |cache_key|
      key_without_locale = extract_key_without_locale(cache_key)
      update_localization_key(key_without_locale) if hits_counter['hits_tracker.' + key_without_locale] == 'true'
    end
    
    remove_hits_tracker_keys(hits_counter, hits_tracker_keys)
  end

  private

  def get_hits_counter
    Lit.init.cache.instance_variable_get(:@hits_counter)
  end

  def get_hits_tracker_keys(hits_counter)
    return [] unless hits_counter.respond_to?(:keys)
    
    all_keys = hits_counter.keys
    all_keys.select { |key| key.to_s.start_with?('lit:elvium_lit:hits_tracker.') }
  end

  def extract_key_without_locale(cache_key)
    cache_key.split('lit:elvium_lit:hits_tracker.').last
  end

  def update_localization_key(key_without_locale)
    localization_key = Lit::LocalizationKey.find_by(localization_key: key_without_locale)

    localization_key.update(last_visited_at: 1.day.ago.to_date) if localization_key
  end

  def remove_hits_tracker_keys(hits_counter, hits_tracker_keys)
    hits_tracker_keys.each do |cache_key|
      hits_counter.delete(cache_key.split('lit:elvium_lit:').last)
    end
  end
end

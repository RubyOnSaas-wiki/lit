class SynchronizeSourceService
  def initialize(source)
    @source = source
  end

  # The remote's newest change is read before its rows, so anything it changes
  # while they are imported falls inside the next sync's window.
  def execute
    last_change = fetch_last_change
    synchronize_localizations
    update_timestamps(last_change)
  end

  private

  def synchronize_localizations
    after_date = @source.last_updated_at&.to_formatted_s(:db)
    result = interactor.send_request Lit::Source::LOCALIZATIONS_PATH, after: after_date
    return unless result&.is_a?(Array)
    result.each { |loc| synchronize_localization loc }
  end

  def synchronize_localization(loc)
    inc_loc = find_incomming_localization(loc)
    inc_loc.source = @source
    inc_loc.locale_str = loc['locale_str']
    inc_loc.locale = Lit::Locale.find_by(locale: loc['locale_str'])
    inc_loc.localization_key_str = loc['localization_key_str']
    inc_loc.localization_key_is_deleted = localization_key_deleted?(loc)
    inc_loc.localization_key = find_localization_key(inc_loc)
    inc_loc.translated_value = loc['value']
    return if inc_loc.duplicated?(loc['value'])

    inc_loc.save!
  end

  def find_incomming_localization(localization)
    Lit::IncommingLocalization.find_or_initialize_by(incomming_id: localization['id'])
  end

  def find_localization_key(inc_loc)
    Lit::LocalizationKey.find_by(localization_key: inc_loc.localization_key_str)
  end

  def localization_key_deleted?(loc)
    loc['localization_key_is_deleted'] || false
  end

  # The remote returns rows changed at least a second after this date. Going
  # back one second keeps rows written later in that same second; fetching a row
  # twice is harmless, it updates the same incoming record or is skipped as a
  # duplicate.
  def update_timestamps(last_change)
    @source.assign_last_updated_at(last_change)
    @source.last_updated_at -= 1.second
    @source.sync_complete = true
    @source.save!
  end

  def fetch_last_change
    interactor.send_request(Lit::Source::LAST_CHANGE_PATH)['last_change']
  end

  def interactor
    RemoteInteractorService.new(@source)
  end
end

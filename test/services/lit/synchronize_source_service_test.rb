require 'test_helper'

# Applicable only in an ActiveJob-enabled environment (Rails 4.2+ or 4.0/4.1
# with additional gem)
if defined?(ActiveJob)
  module Lit
    class SynchronizeSourceServiceTest < ActiveSupport::TestCase
      fixtures :all

      def setup
        after = 3.hours.ago
        after_str = after.strftime('%F %T')
        after_param = Rack::Utils.escape(after_str)
        @source = Source.first
        @source.update_column(:last_updated_at, after)
        @localizations_addr = localizations_addr = "http://testhost.com/lit/api/v1/localizations.json?after=#{after_param}"
        @last_change_addr = last_change_addr = 'http://testhost.com/lit/api/v1/last_change.json'
        stub_request(:get, localizations_addr).to_return(
          body:
            Localization
              .all
              .as_json(
                root: false,
                only: %i[id localization_key_id locale_id],
                methods: %i[value localization_key_str locale_str localization_key_is_deleted],
              )
              .to_json,
        )
        stub_request(:get, last_change_addr).to_return(body: { last_change: after_str }.to_json)
      end

      test 'synchronization works for different values' do
        assert_equal 0, @source.incomming_localizations.count
        Localization.all.each do |lc|
          lc.translated_value << 'test'
          lc.is_changed = true
          lc.save
        end
        SynchronizeSourceService.new(@source).execute
        assert_equal 5, @source.incomming_localizations.count
      end

      # The remote answers with the newest change it has at that moment; a row
      # accepted there while we import must still be inside the next window, which
      # opens one second after the date we keep.
      test 'a row changed on the remote during a sync is picked up by the next one' do
        newest_change = '2026-11-08 12:00:05'
        stub_request(:get, @last_change_addr).to_return(lambda do |_request|
          { body: { last_change: newest_change }.to_json }
        end)
        stub_request(:get, @localizations_addr).to_return(lambda do |_request|
          newest_change = '2026-11-08 12:00:09'
          { body: [].to_json }
        end)

        SynchronizeSourceService.new(@source).execute

        assert_equal Time.zone.parse('2026-11-08 12:00:04'), @source.reload.last_updated_at
      end

      test 'synchronization ignores same values' do
        assert_equal 0, @source.incomming_localizations.count
        SynchronizeSourceService.new(@source).execute
        assert_equal 0, @source.incomming_localizations.count
      end
    end
  end
end

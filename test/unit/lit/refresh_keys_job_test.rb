require 'test_helper'

module Lit
  class RefreshKeysJobTest < ActiveSupport::TestCase
    setup do
      Lit::RefreshKeysJob.release_guard
      @previous_cache = ::Rails.cache
    end

    teardown do
      ::Rails.cache = @previous_cache
      Lit::RefreshKeysJob.release_guard
    end

    test 'the guard is claimed once and refused until released' do
      assert Lit::RefreshKeysJob.claim_guard
      assert_not Lit::RefreshKeysJob.claim_guard

      Lit::RefreshKeysJob.release_guard
      assert Lit::RefreshKeysJob.claim_guard
    end

    # Elvium runs `config.cache_store = :null_store` in development, where a
    # Rails.cache-only guard silently never holds and every request would launch
    # another full YAML scan.
    test 'the guard still holds when the host cache store discards everything' do
      ::Rails.cache = ActiveSupport::Cache::NullStore.new

      assert Lit::RefreshKeysJob.claim_guard
      assert_not Lit::RefreshKeysJob.claim_guard
    end

    test 'performing releases the guard even when the backend cannot refresh' do
      Lit::RefreshKeysJob.claim_guard
      ::I18n.backend.stubs(:respond_to?).with(:init_translations_with_caching).returns(false)

      Lit::RefreshKeysJob.new.perform

      assert Lit::RefreshKeysJob.claim_guard, 'guard was not released'
    end
  end
end

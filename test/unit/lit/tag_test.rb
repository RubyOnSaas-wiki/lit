require 'test_helper'

module Lit
  class TagTest < ActiveSupport::TestCase
    setup do
      @lk = Lit::LocalizationKey.create!(localization_key: 'tag.test.key')
    end

    test 'normalizes name to a stripped, downcased slug' do
      tag = Lit::Tag.create!(name: '  Dev-958  ')
      assert_equal 'dev-958', tag.name
    end

    test 'name is unique after normalization' do
      Lit::Tag.create!(name: 'billing')
      duplicate = Lit::Tag.new(name: ' Billing ')
      assert_not duplicate.valid?
    end

    test '.find_or_create_normalized returns the existing tag for a differently cased name' do
      existing = Lit::Tag.create!(name: 'hr-tree')
      assert_equal existing, Lit::Tag.find_or_create_normalized('HR-Tree')
      assert_equal 1, Lit::Tag.count
    end

    test 'round-trips through the join table from both sides' do
      tag = Lit::Tag.create!(name: 'billing')
      @lk.tags << tag

      assert_equal [tag], @lk.reload.tags.to_a
      assert_equal [@lk], tag.reload.localization_keys.to_a
      assert_equal 1, Lit::Tag.joins(:localization_keys).count
    end

    test 'destroying a localization key removes its tag joins but keeps the tag' do
      tag = Lit::Tag.create!(name: 'billing')
      @lk.tags << tag
      @lk.destroy

      assert_equal 0, Lit::LocalizationKeyTag.count
      assert Lit::Tag.exists?(tag.id)
    end
  end
end

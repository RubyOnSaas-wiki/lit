class LitCleanupDuplicateLocalizationKeys < ActiveRecord::Migration[4.2]
  def up
    duplicates = Lit::LocalizationKey.group(:localization_key).having('COUNT(*) > 1').pluck(:localization_key)

    duplicates.each do |localization_key|
      keys = Lit::LocalizationKey.where(localization_key: localization_key).order(:created_at)
      
      primary_key = keys.first.localizations.length > 1 ? keys.first : keys.last
      duplicate_keys = keys - [primary_key]
      
      duplicate_keys.each(&:delete)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

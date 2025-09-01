class LitAddLastVisitedAtToLocalizationKey < ActiveRecord::Migration[4.2]
  def change
    add_column :lit_localization_keys, :last_visited_at, :date
  end
end

# Splits the AI translated tab into new translations and corrections of a
# translation that already exists. Recorded when the proposal is made, so the
# tab can filter and paginate in SQL; `rake lit:ai_suggestions:reclassify` sorts
# proposals recorded before this column existed.
class LitAddIsCorrectionToLitAiSuggestions < ActiveRecord::Migration[5.2]
  def up
    return if column_exists?(:lit_ai_suggestions, :is_correction)

    add_column :lit_ai_suggestions, :is_correction, :boolean, default: false, null: false
  end

  def down
    remove_column :lit_ai_suggestions, :is_correction
  end
end

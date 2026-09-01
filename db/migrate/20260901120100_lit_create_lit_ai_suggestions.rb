# Migration[5.2] rather than the [4.2] the older lit migrations use: in 4.2
# compatibility mode new tables get a plain `integer` primary key, which hosts
# running online_migrations reject as a wraparound risk. 5.2 is the gem's minimum
# supported Rails, so this is valid on every version lit supports.
# The foreign key columns stay `integer`: the lit tables they point at have
# `integer` (serial) primary keys.
class LitCreateLitAiSuggestions < ActiveRecord::Migration[5.2]
  def up
    return if table_exists?(:lit_ai_suggestions)

    create_table :lit_ai_suggestions do |t|
      t.integer :localization_key_id, null: false
      t.integer :locale_id, null: false
      t.text :suggested_value
      t.text :base_value
      t.string :provider
      t.boolean :is_edited, default: false, null: false

      t.timestamps
    end

    add_index :lit_ai_suggestions, %i[localization_key_id locale_id],
              unique: true, name: 'index_lit_ai_suggestions_on_key_and_locale'
    add_index :lit_ai_suggestions, :locale_id
  end

  def down
    drop_table :lit_ai_suggestions
  end
end

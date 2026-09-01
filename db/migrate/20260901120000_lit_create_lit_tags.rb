class LitCreateLitTags < ActiveRecord::Migration[4.2]
  def up
    unless table_exists?(:lit_tags)
      create_table :lit_tags do |t|
        t.string :name, null: false

        t.timestamps
      end
      add_index :lit_tags, :name, unique: true
    end

    return if table_exists?(:lit_localization_key_tags)

    create_table :lit_localization_key_tags do |t|
      t.integer :localization_key_id, null: false
      t.integer :tag_id, null: false

      t.timestamps
    end
    add_index :lit_localization_key_tags, %i[localization_key_id tag_id],
              unique: true, name: 'index_lit_localization_key_tags_on_key_and_tag'
    add_index :lit_localization_key_tags, :tag_id
  end

  def down
    drop_table :lit_localization_key_tags
    drop_table :lit_tags
  end
end

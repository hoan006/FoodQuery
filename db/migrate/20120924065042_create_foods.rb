class CreateFoods < ActiveRecord::Migration
  def up
    create_table :foods do |t|
      t.string :source
      t.string :brand
      t.string :group
      t.string :name
      t.text :link
      t.timestamps
    end
    execute "CREATE INDEX food_name_idx ON foods USING gin(to_tsvector('english', name));"
  end

  def down
    drop_table :foods
  end
end

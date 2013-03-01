class CreateServings < ActiveRecord::Migration
  def change
    create_table :servings do |t|
      t.integer :food_id
      t.text :name
      t.string :size
      t.decimal :calories
      t.string :fat
      t.string :carbohydrates
      t.string :protein

      t.timestamps
    end
  end
end

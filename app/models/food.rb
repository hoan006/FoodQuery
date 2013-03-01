class Food < ActiveRecord::Base
  attr_accessible :brand, :group, :source, :link, :name
  has_many :servings

  define_index do
    indexes :name, :sortable => true
    indexes :group
    indexes :brand
    indexes servings.name, :as => :serving_type
    has servings.calories, :as => :serving_calories
    has "CAST(array_length(regexp_split_to_array(foods.name, ' '), 1) AS INT)", :type => :integer, :as => :words_count, :sortable => true
  end
end

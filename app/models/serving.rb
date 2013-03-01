class Serving < ActiveRecord::Base
  attr_accessible :name, :size, :calories, :carbohydrates, :fat, :food_id, :protein
  belongs_to :food
  
  define_index do
    indexes name
    has calories, :type => :integer
    has food_id
  end
end

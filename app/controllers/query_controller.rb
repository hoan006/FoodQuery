class QueryController < ApplicationController
  before_filter :authenticate

  def index
    [:name, :group, :brand, :from_calories, :to_calories, :serve_type].each do |sym|
      instance_variable_set "@#{sym.to_s}", params[sym].try(:strip)
    end
    @name = @name.gsub(/-/, ' !').gsub(/ /, '&').gsub(/&+/, '&').gsub(/&+\|&+/, '|') if @name.present?

    start_time = Time.now

    conditions = {} 
    conditions[:name] = @name if @name.present?
    conditions[:group] = @group if @group.present?
    conditions[:brand] = @brand if @brand.present?
    conditions[:serving_type] = @serve_type if @serve_type.present?

    from_calories = @from_calories.present? ? @from_calories.to_i : 0
    to_calories = @to_calories.present? ? @to_calories.to_i : 9999999

    @foods = Food.search(
      :conditions => conditions,
      :include => :servings,
      :page => params[:page], :per_page => 100,
      :rank_mode => :wordcount,
      :sort_mode => :extended, :order => "#{'words_count ASC, @relevance DESC, ' if @name.present?}name ASC",
      :with => {:serving_calories => from_calories..to_calories}
    )

    @serving_ids = Serving.search(
      :conditions => @serve_type.present? ? {:name => @serve_type} : {},
      :with => {:calories => from_calories..to_calories,
                :food_id => @foods.map(&:id)},
      :page => 1, :per_page => 1000
    ).map(&:id)

    @time_cost = "Time: #{Time.now - start_time}s"
    respond_to do |format|
      format.html
      format.json do
        result = []
        @foods.select{|f| (f.serving_ids & @serving_ids).present?}.each do |food|
          clone_food = food.dup
          food.servings.each do |serving|
            clone_food.servings << serving.dup if @serving_ids.include? serving.id
          end
          result << clone_food
        end
        render :json => result.to_json(:include => :servings)
      end
    end
  end

  protected

  def authenticate
    authenticate_or_request_with_http_basic do |username, password|
      username == "misfit" && password == "User@123"
    end
  end
end

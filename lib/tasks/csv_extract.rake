require 'csv'
require 'iconv'

namespace "fq" do
  desc "Truncate all tables"
  task :truncate => :environment do
    ActiveRecord::Base.connection.tables.each do |table|
      ActiveRecord::Base.connection.execute("TRUNCATE #{table}")
    end
  end
  
  desc "Convert XLS to CSV"
  task :xls2csv => :environment do
    folder = File.join(Rails.root, "lib/assets/XLS")
    dest_folder = File.join(Rails.root, "lib/assets/CSV/")
    Dir.mkdir(dest_folder) unless Dir.exists?(dest_folder)

    Dir.foreach(folder) do |sub_name|
      # ignore file types or system folders
      next if sub_name.match(/^\./)
      sub_folder = File.join(folder, sub_name)
      next unless Dir.exists?(sub_folder)

      # create corresponding sub folders
      dest_sub_folder = File.join(dest_folder, sub_name)
      Dir.mkdir(dest_sub_folder) unless Dir.exists?(dest_sub_folder)

      Dir.foreach(sub_folder) do |file_name|
        next if !file_name.end_with?(".xls") && !file_name.end_with?(".xlsx")
        puts "Converting file [%s]" % file_name
        xls = (file_name.end_with?(".xls") ? Excel : Excelx).new File.join(sub_folder, file_name)
        xls.sheets.each do |sheet|
          xls.default_sheet = sheet
          xls.to_csv (File.join(dest_sub_folder, file_name.gsub(/\.xls(x)*/, "(#{sheet}).csv"))).to_s
        end
      end
    end
  end
  
  desc "Extract data from CSV files and import to database"
  task :import_from_csv => :environment do
    folder = File.join(Rails.root, "lib/assets/CSV")
    Dir.foreach(folder) do |sub_name|
      next if sub_name.match(/^\./)
      sub_folder = File.join(folder, sub_name)
      next unless Dir.exists?(sub_folder)
      if (sub_name.match /^all/i) && (sub_name.match /recipe/i)
        import_type_1(sub_folder, sub_name)
      elsif sub_name.match /myfitnesspal/i
        import_type_2(sub_folder, sub_name)
      else
        import_type(sub_folder, sub_name)
      end
    end
    FileUtils.rm_rf folder if Rails.env != "development"
  end
  
  # for AllRecpies
  def import_type_1(sub_folder, sub_name) 
    size_multiply = lambda { |value_string, size| value_string.nan? ? value_string : (value_string.to_f * size).round(6).to_s }   
    reworked_rows = []
    
    Dir.foreach(sub_folder) do |file_name|
      next if !file_name.end_with? ".csv"
      puts "**Subcategory [%s]**" % file_name[0, file_name.length - 4]
      source = sub_name
      calories = fat = carbohydrates = protein = nil
      recipe_serving = servings_per_recipe = nil
      current_idx = 0
      new_food = Food.new
      file = File.open(File.join(sub_folder, file_name), "rb")
      file_contents = file.read
      ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
      file_contents = ic.iconv(file_contents + ' ')[0..-2]
      file.close
      
      previous_row = nil
      csv = CSV.parse(file_contents) do |row|
        row[0] = row[0].to_s.gsub(',', '')
        if row[0].to_i > 0
          puts '- Wrong numbering: %d -> %d' % [current_idx, row[0].to_i] if row[0].to_i - current_idx != 1 && !(current_idx > 1 && row[0].to_i == 1)
          current_idx = row[0].to_i
          
          # commit food to database
          if new_food
            if new_food.name.present?
              new_food.source = source
              
              # old version of regex: /^\s*(\d+)\s+[\D]*((\(.*\))|(\d+\s*x\s*\d+))?[\D]*$/
              matches = recipe_serving.match /^\s*(\d+\.?\d*)\s+-?\s*((\D*((\(.*\))|(\d+\s*x\s*\d+))?\D*$)|((\d+\.?\d*\D+)?(\D*(\d+\.?\d*(x\d+\.?\d*)*-\D+)|\(.*\))*\D*$))/
              if matches.nil?
                matches = recipe_serving.match /^\s*\d+\.?\d*\sto\s\d+\.?\d*(\D*)$/
                if matches.present?
                  serving_name = matches[1].strip.singularize
                  sizef = servings_per_recipe.to_i
                else
                  reworked_rows << [file_name[0..-5]] + previous_row
                end
              else
                recipe_size = [matches[1].to_i, 1].max
                serving_name = matches[2].strip.singularize
                sizef = servings_per_recipe.to_i / recipe_size
              end

              if matches.present?
                new_food.servings.build({
                  name: serving_name,
                  calories: size_multiply.call(calories, sizef),
                  fat: size_multiply.call(fat, sizef),
                  carbohydrates: size_multiply.call(carbohydrates, sizef),
                  protein: size_multiply.call(protein, sizef)
                })

                new_food.servings.build({
                  name: "serving",
                  calories: calories,
                  fat: fat,
                  carbohydrates: carbohydrates,
                  protein: protein
                }) if serving_name != "serving"
              end

              new_food.save!
            end
            new_food = Food.new
          end
          
          # Name
          new_food.name = row[1].try(:strip)
          
          # Recipe serving
          recipe_serving = row[2].try(:strip)
          servings_per_recipe = row[3].try(:strip)

          if recipe_serving.blank?
            puts '- No. %d: Missing recipe serving' % current_idx
            new_food = Food.new
            next
          end

          # Calories
          if row[4].to_f > 0 || row[4].to_s.match(/^0((\.)0*)?$/)
            calories = row[4].to_f
          else
            if row[4].to_s.length == 0
              puts '- No. %d: Missing calorie' % current_idx
            else
              puts '- No. %d: Wrong calorie [%s]' % [current_idx, row[4]]
            end
            new_food = Food.new
            next
          end

          # Fat, Carbohydrates & Protein
          fat = row[5].to_s.strip
          carbohydrates = row[6].to_s.strip
          protein = row[7].to_s.strip

          # Link
          new_food.link = row[8].to_s.strip
          previous_row = row
        end
      end
    end
    
    if reworked_rows.present?
      CSV.open(File.join(Rails.root, "lib/assets/reworked_rows.csv"), "wb") do |csv|
        csv << ["File(Sheet)", "No.", "Food Name", "Recipe serving", "Serving/recipe", "Calories/serving", "Carbohydrates", "Fat", "Protein", "Link"]
        reworked_rows.each {|r| csv << r}
      end
    end
  end

  # for MyFitnessPal
  def import_type_2(sub_folder, sub_name) 
    size_multiply = lambda { |value_string, size| value_string.nan? ? value_string : (value_string.to_f * size).round(6).to_s }   
    Dir.foreach(sub_folder) do |file_name|
      next if !file_name.end_with? ".csv"
      puts "**Subcategory [%s]**" % file_name[0, file_name.length - 4]
      source = sub_name
      current_idx = 0
      new_food = Food.new
      file = File.open(File.join(sub_folder, file_name), "rb")
      file_contents = file.read
      ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
      file_contents = ic.iconv(file_contents + ' ')[0..-2]
      file.close
      first_row = true
      csv = CSV.parse(file_contents) do |row|
        current_idx += 1
        first_row = false and next if first_row

        # Food name, brand and source
        str_name = row[0].to_s.strip
        puts "Missing food name at row %s" % current_idx and next if str_name.blank?
        str_brand = row[1].to_s.strip
        if new_food.name != str_name || new_food.brand != str_brand
          new_food.save!
          new_food = Food.new({name: str_name, brand: str_brand, source: source})
        end

        # Serve type
        serving = Serving.new
        serving.name = row[2].to_s.strip
        puts "Missing serving type at row %s" % current_idx and next if serving.name.blank?

        # Calories
        serving.calories = row[3].to_f
        puts "Missing or incorrect calories at row %s" % current_idx and next if serving.calories == 0

        # Fat, Carbohydrates & Protein
        serving.fat = row[5].to_s.strip
        serving.carbohydrates = row[11].to_s.strip
        serving.protein = row[14].to_s.strip

        # Link
        new_food.link = row[20].to_s.strip
        new_food.servings << serving
      end
      new_food.save! if new_food.name.present?
    end
  end

  # for CaloriesKing & FatSecret
  def import_type(sub_folder, sub_name) 
    size_multiply = lambda { |value_string, size| value_string.nan? ? value_string : (value_string.to_f * size).round(6).to_s }   
    Dir.foreach(sub_folder) do |file_name|
      next if !file_name.end_with? ".csv"
      puts "**Subcategory [%s]**" % file_name[0, file_name.length - 4]
      source = sub_name
      group = nil
      current_idx = 0
      svr_types = svr_sizes = []
      calories_per_oz = fat_per_oz = carbohydrates_per_oz = protein_per_oz = nil
      new_food = Food.new
      file = File.open(File.join(sub_folder, file_name), "rb")
      file_contents = file.read
      ic = Iconv.new('UTF-8//IGNORE', 'UTF-8')
      file_contents = ic.iconv(file_contents + ' ')[0..-2]
      file.close
      csv = CSV.parse(file_contents) do |row|
        row[0] = row[0].to_s.gsub(',', '')
        if row[0].to_i > 0
          puts '- Wrong numbering: %d -> %d' % [current_idx, row[0].to_i] if row[0].to_i - current_idx != 1 && !(current_idx > 1 && row[0].to_i == 1)
          current_idx = row[0].to_i

          # commit food to database
          if new_food
            if new_food.name.present?
              new_food.source = source
              will_add_oz_serving = true
              svr_sizes.each_with_index do |size, index|
                sizef = size.to_f
                if size.nan? || size.to_f == 0
                  size = nil unless size.match /^0((\.)0*)?$/
                  sizef = 1
                  will_add_oz_serving = false
                else
                  size += " oz"
                end
                serving = new_food.servings.build({
                  name: svr_types[index],
                  size: size,
                  calories: size_multiply.call(calories_per_oz, sizef),
                  fat: size_multiply.call(fat_per_oz, sizef),
                  carbohydrates: size_multiply.call(carbohydrates_per_oz, sizef),
                  protein: size_multiply.call(protein_per_oz, sizef)
                })
              end
              if will_add_oz_serving
                serving = new_food.servings.build({
                  name: "oz",
                  size: "1 oz",
                  calories: calories_per_oz,
                  fat: fat_per_oz,
                  carbohydrates: carbohydrates_per_oz,
                  protein: protein_per_oz
                })
              end

              new_food.save!
            end
            new_food = Food.new
          end

          # Brand
          new_food.brand = row[1].to_s.strip

          # Group
          new_food.group = group

          # Name
          row.insert(3, nil) if row[2].present? && row[3].present?
          new_food.name = (row[2].present? ? row[2] : row[3]).try(:strip)

          # Serving sizes
          svr_types = row[4].to_s.split(/\r|\n|_x000D_/).map(&:strip).reject(&:blank?)
          svr_sizes = row[5].to_s.split(/\r|\n|_x000D_/).map(&:strip).reject(&:blank?)

          if svr_types.size != svr_sizes.size
            puts '- No. %d: Wrong serving size or serving type' % current_idx
            new_food = Food.new
            next
          end

          # Calories
          if row[6].to_f > 0 || row[6].to_s.match(/^0((\.)0*)?$/)
            calories_per_oz = row[6].to_f
          else
            if row[6].to_s.length == 0
              if 1.upto(5).any? {|i| row[i].to_s.length > 0}
                puts '- No. %d: Missing calorie or row merged incorrectly' % current_idx
              end
            else
              puts '- No. %d: Wrong calorie [%s]' % [current_idx, row[6]]
            end
            new_food = Food.new
            next
          end

          # Fat, Carbohydrates & Protein
          fat_per_oz = row[7].to_s.strip
          carbohydrates_per_oz = row[8].to_s.strip
          protein_per_oz = row[9].to_s.strip

          # Link
          new_food.link = row[10].to_s.strip

        elsif row[0].blank? && row[1].blank? && row[2].blank? && row[3].blank? &&
          row[4].present? && row[5].present? && new_food.try(:name).present?
          svr_types += row[4].to_s.split(/\r|\n|_x000D_/).map(&:strip).reject(&:blank?)
          svr_sizes += row[5].to_s.split(/\r|\n|_x000D_/).map(&:strip).reject(&:blank?)

          if svr_types.size != svr_sizes.size
            puts '- No. %d: Wrong serving size or serving type' % current_idx
            new_food = Food.new
            next
          end
        elsif row[1] == 'Group'
          if (new_group = row[2].to_s.strip) && new_group != group
            group = new_group
            puts '### Group [%s]' % group
          end
        end
      end
      if new_food.name.present?
        new_food.source = source
        will_add_oz_serving = true
        svr_sizes.each_with_index do |size, index|
          if size.nan? || size.to_f == 0
            size = 1
            will_add_oz_serving = false
          else
            size = size.to_f
          end
          serving = new_food.servings.build({
            name: svr_types[index],
            calories: size_multiply.call(calories_per_oz, size),
            fat: size_multiply.call(fat_per_oz, size),
            carbohydrates: size_multiply.call(carbohydrates_per_oz, size),
            protein: size_multiply.call(protein_per_oz, size)
          })
        end
        if will_add_oz_serving
          serving = new_food.servings.build({
            name: "oz",
            calories: calories_per_oz,
            fat: fat_per_oz,
            carbohydrates: carbohydrates_per_oz,
            protein: protein_per_oz
          })
        end
        new_food.save!
      end
    end
  end
end

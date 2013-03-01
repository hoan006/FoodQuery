require 'mechanize'

namespace 'crawler' do
  desc "Crawl All Recipes' categories"
  task :all_recipes_categories => :environment do
    base_url = 'http://allrecipes.com'
    home_url = 'http://allrecipes.com/Recipes/Main.aspx'
    agent = Mechanize.new

    crawler_folder = File.join(Rails.root, 'lib/assets/crawler')
    Dir.mkdir(crawler_folder) unless Dir.exists?(crawler_folder)

    CSV.open(File.join(crawler_folder, 'all_recipes_categories.csv'), 'wb') do |csv|
      csv << ['Category Level', 'Category Name', 'Food', 'Link']
      current_level = 1
      agent.get(home_url).search('#left ul > li a').each do |node|
        crawl_categories_from_node(agent, node, base_url, csv, current_level)
      end
    end
  end

  def crawl_categories_from_node(agent, node, base_url, csv, current_level)
    category = node.inner_html
    url = URI.join(base_url, node['href']).to_s
    puts "#Category level #{current_level}: #{category}"
    puts " #{url}"

    view_all_url = url.gsub(/main.aspx$/i, 'ViewAll.aspx')
    crawl_foods_from_node(agent, view_all_url, base_url, category, csv, current_level)

    html_doc = agent.get(url)
    crawl_deeper = html_doc.search("#left h4:first").first.try(:inner_html) == "Browse Deeper"
    if crawl_deeper
      html_doc.search('#left ul > li a').each do |sub_node|
        crawl_categories_from_node(agent, sub_node, base_url, csv, current_level + 1)
      end
    end
  end
  
  def crawl_foods_from_node(agent, view_all_url, base_url, category, csv, current_level)
    html_doc = agent.get(view_all_url)
    html_doc.search('#yay h3 a').each do |food_node|
      food_name = food_node.inner_html
      food_url = URI.join(base_url, food_node['href']).to_s
      puts "            *Food: #{food_name}"

      csv << [current_level, category, food_name, food_url]
    end

    last_navigation_node = html_doc.search('.page_navigation_nav span a:last').first
    if last_navigation_node && last_navigation_node.inner_html.match(/next/i)
      next_page_url = last_navigation_node['href']
      crawl_foods_from_node(agent, next_page_url, base_url, category, csv, current_level)
    end
  end
end
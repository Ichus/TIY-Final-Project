require "neo4j-core"

class WikiRelations
  def initialize
    @continue = true
  end

  def run
    puts "Enter: 1 to test an Idea's relationships."
    puts "Enter: 2 to test an Idea's categories."
    puts "Enter: 3 to test an Idea's categories."
    input = gets.chomp.to_i
    case input
    when 1
      relations_test
    when 2
      category_test
    when 3
      category_relations_test
    else
      puts "Invalid choice"
      run
    end
  end

  def relations_test
    while @continue do
      puts "Enter an Idea to see what's related."
      idea = gets.chomp
      # related = relations idea
      relations idea
      # if related.first
      #   related.each
      # else
      #   puts "I'm a lowly macbook, I haven't heard of this #{idea}. I'll learn more about it sometime"
      # end
      continue?
    end
    puts "Goodbye"
  end

  def relations(idea)
    nodey = Neo4j::Node.find("idea: #{idea.inspect}~")
    if nodey.first
      node = nodey.first
      nodey.close
      node.outgoing(:relation).filter{|path| path.relationships.first[:weight] > 0.7515 && !/#{node[:idea]}/i.match(path.end_node[:idea]) }.each {|rel| puts "#{rel[:idea]}"}
    else
      puts "Still crunching data. Nothing on #{idea} yet. Check back soon."
    end
  end

  def category_relations_test
    while @continue do
      puts "Enter an Idea to see one of its categories relations."
      idea = gets.chomp
      print_cat_relations(categories(idea, :category_relations), idea)
      continue?
    end
    puts "Goodbye"
  end

  def print_cat_relations(category, idea)
    nodey = Neo4j::Node.find("idea: #{idea.inspect}")
    if nodey.first
      node = nodey.first
      nodey.close
      puts "Category: #{category}"
      node.outgoing(:relation).filter do |path|
        path.relationships.first[:weight] > 0.55 &&
        /#{category}/.match(path.relationships.first[:category]) &&
        !/#{node[:idea]}/i.match(path.end_node[:idea])
      end.first(10).each { |rel| puts "Relation: #{rel[:idea]}" }
    end
  end

  def continue?
    puts "Would you like me to examine another idea?"
    input = gets.chomp
    if input == "y" || input == "Y" || /yes/i.match(input)
      @continue = true
    elsif input == "n" || input == "N" || /no/i.match(input)
      @continue = false
    else
      puts "You must enter yes or no. (y/n)"
      continue?
    end
  end

  def category_test
    while @continue do
      puts "Enter an Idea to see its categories."
      idea = gets.chomp
      categories(idea, :category)
      continue?
    end
    puts "Goodbye"
  end


  # Discovered A has categories stored that aren't visible on the web page????
  def categories(idea, flag)
    categories = []
    nodey = Neo4j::Node.find("idea: #{idea.inspect}~")
    if nodey.first
      node = nodey.first
      nodey.close
      node.rels.each do |rel|
        category = rel["category"]
        category_flag = category.chars.first.to_i
        category = category.slice(1..-1)
        already_found = false
        categories.each { |cat| already_found = true if cat[1].eql? category }
        categories << [category_flag, category] unless already_found
      end
      if flag == :category
        print_categories categories
      elsif flag == :category_relations
        categories.first[1]
      end
    else
      puts "Still crunching data. Nothing on #{idea} yet. Check back soon."
    end
  end

  def print_categories(categories)
    categories.reverse_each do |cat|
      tabs = cat[0]
      category = cat[1]
      tabs.times {  print "  " }
      print "#{category}\n"
    end
  end
end

wiki_relate = WikiRelations.new
wiki_relate.run

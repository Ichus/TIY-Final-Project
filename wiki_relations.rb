require "neo4j-core"

class WikiRelations
  def initialize
    @continue = true
  end

  def run
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
      puts "I'm a lowly macbook, I haven't heard of this #{idea}. I'll learn more about it sometime"
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
end

wiki_relate = WikiRelations.new
wiki_relate.run

require "nokogiri"
require "neo4j-core"

# Open Wikipedia Pages XML composed of articles and redirect articles
wiki_xml = File.open(File.join("wiki_dump", "enwiki-20140707-pages-articles.xml"))

# Same as Wikipedia Pages Parser but with most terminal output removed.
class WikiExtract < Nokogiri::XML::SAX::Document
  def initialize
    @element_case = 0
    @title = ""
    @heading = ""
    @sub_heading = ""
    @paragraph_heading = ""
    @ns = false
    @redirect = false
    @redirect_title = ""
    @pages = 0
    @heading_flag = false
    @heading_switch = 0
    @link_weight = 0
    @excluded_categories = ["External links", "Further reading", "References",
                            "See also", "Notes", "Footnotes", "Bibliography"]
  end

  def end_document
    puts "END WIKI DUMP - #{@pages} Pages Parsed - END WIKI DUMP"
  end

  def start_element(element, attributes = [])
    case element
    when "title"
      @element_case = :title
    when "ns"
      @element_case = :ns
    # when /redirect.*/
    #   @redirect = true
    when "text"
      @element_case = :text
    when "timestamp"
      save_article_to_neo if @ns && !@redirect
    else
      @element_case = 0
    end
    if /redirect.*/.match(element)
      @redirect = true
    end
    if element == "page"
      puts "Page: #{@pages}"
      @pages += 1
    end
  end

  def end_element(element)
    # Sets redirect flag to false in preparation for parsing the next element
    if element == "page"
      @redirect = false
      @ns = false
    end
    @element_case = 0
  end

  def characters(string)
    string.strip!
    case @element_case
    when :title
      extract_title string
    when :ns
      # Set this up so pages that aren't articles won't be saved into the database
      @ns = true if string == "0"
      # puts "It is -- #{@ns.to_s} -- that this page should be stored in the database"
    when :text
      !@redirect ? parse_text(string) : parse_redirect(string)
    when 0
      # puts "element I'm not interested in"
    end
  end

  def head_switch
    case @heading_switch
    when :title
      "0#{prep_header(@title)}"
    when :head
      "1#{prep_header(@heading)}"
    when :sub_head
      "2#{prep_header(@sub_heading)}"
    when :paragraph
      "3#{prep_header(@paragraph_heading)}"
    else
      "This Link Doesn't Belong To Anyone????"
    end
  end

  def prep_header(header)
    numeral_header = /[^=]?[^=]*[^=]/.match(header)
    # For some reason there are headers in the wiki-text which are some length of "======"
    # This will catch those and change them to "External links", which is excluded
    numeral_header ? numeral_header = numeral_header[0] : numeral_header = "External Links"
  end

  def heading_switch(header_sym)
    @heading_switch = header_sym
    case header_sym
    when :title
      @link_weight = 0.754
    when :paragraph
      @link_weight = 0.684
    when :sub_head
      @link_weight = 0.724
    when :head
      @link_weight = 0.744
    else
      @link_weight = "bananas"
    end
  end

  def decrement_link_weight
    @link_weight *= 0.99972 # Change to 0.99992 if going with 3 decimals places instead of 2. or 0.99999
  end

  def extract_title(title)
    @title = title
    puts "Title: #{@title}"
    heading_switch :title
  end

  def parse_redirect(text)
    @redirect_title = /#REDIRECT \[\[.*/.match(text)
    @redirect_title = @redirect_title[0].slice(12..-1) if @redirect_title
    puts "Redirect Page. [AltArticleName, RedirectTo] [#{@title}, #{@redirect_title}]" if @redirect_title
  end

  def parse_text(text)
    link = /\[\[.*\|/.match(text)
    link ? link = /\[\[.*[^\|]/.match(link[0]) : link = /\[\[.*/.match(text)
    if link
      stripped_link = link[0].slice!(2..-1)
      process_link stripped_link if stripped_link
    elsif @heading_flag
      heading_link = /{{.*/.match(text)
      process_heading_link heading_link if heading_link
    else
      paragraph_header = /={4}[\w\s-]*={4}/.match(text)
      process_paragraph paragraph_header if paragraph_header
      unless paragraph_header
        sub_header = /={3}[\w\s-]*={3}/.match(text)
        process_sub_header sub_header if sub_header
      end
      unless sub_header || paragraph_header
        header = /==.*==/.match(text)
        process_header header if header
      end
    end
    # paragraph_header || sub_header || header ? @heading_flag = true : @heading_flag = false
    @heading_flag = paragraph_header || sub_header || header
  end

  def process_link(link)
    if !/:/.match(link)
      # puts "Link: #{link} Subbd: #{head_switch} Weight: #{@link_weight}"
      save_link_to_neo(link, @link_weight) if @ns
      decrement_link_weight
    end
  end

  def process_heading_link(heading_link)
    # puts "Heading Link: #{heading_link[0]} Subbd: #{head_switch} Weight: #{@link_weight}"
    # # heading_link[0] needs further processing before it can be input into the database
    # # need something to split out the multiple links A Regex which splits on pipes
    # # save_link_to_neo be in a .each block for each match. After filtering actual matches into array
    # # save_link_to_neo(heading_link[0], @link_weight) if @ns
  end

  def process_paragraph(paragraph_header)
    # puts "Paragraph-Header: #{paragraph_header[0]} Subbd Sub Header: #{@sub_heading}"
    @paragraph_heading = paragraph_header[0]
    heading_switch :paragraph
  end

  def process_sub_header(sub_header)
    # puts "Sub-Header: #{sub_header[0]} Subbd Header: #{@heading}"
    @sub_heading = sub_header[0]
    heading_switch :sub_head
  end

  def process_header(header)
    # puts "Header: #{header[0]} Subbd Title: #{@title}"
    @heading = header[0]
    heading_switch :head
  end

  def save_article_to_neo
    Neo4j::Transaction.run do
      article_node = Neo4j::Node.find("idea: #{@title.inspect}")
      Neo4j::Node.new(:idea => @title, :typex => 'IdeaNode') unless !!article_node.first
      article_node.close
    end
  end

  def save_link_to_neo(link, link_weight)
    link_category = head_switch
    unless skip_excluded_categories(link_category)
      Neo4j::Transaction.run do
        article_node = Neo4j::Node.find("idea: #{@title.inspect}")
        idea_node = article_node.first
        article_node.close
        link_node = Neo4j::Node.find("idea: #{link.inspect}")
        if link_node.first
          relation_node = link_node.first
        else
          relation_node = Neo4j::Node.new(:idea => link, :typex => 'IdeaNode')
        end
        link_node.close
        rel_traverser = idea_node.rels(:outgoing, :relation).to_other(relation_node)
        unless rel_traverser.first
          idea_link = Neo4j::Relationship.new(:relation, idea_node, relation_node)
          idea_link[:weight] = link_weight
          idea_link[:category] = link_category
          idea_link[:typex] = 'IdeasRelation'
            # need another .rb file to run through the entire graph database and find all the
            # internal_categories it belongs to by stepping through each link. If the category
            # the link belongs to is already in the array don't add it. otherwise add it to
            # the array. At the end save the array as an internal_categories property on the article node
        end
      end
    end
  end

  def skip_excluded_categories(category)
    @excluded_categories.each do |excluded_category|
      return true if /[\d]?[\s]?#{category}[\s]?/.match excluded_category
    end
    return false
  end
end

# Set's trigger to Lucene index the Article nodes in neo4j for finding and sorting via idea name
Neo4j::Node.trigger_on(:typex => 'IdeaNode')
Neo4j::Node.index :idea

# Set's trigger to Lucene index the Link relationships in neo4j for finding and sorting
Neo4j::Relationship.trigger_on(:typex => 'IdeasRelation')
Neo4j::Relationship.index :weight, :field_type => Float
Neo4j::Relationship.index :category

# Create parser
parser = Nokogiri::XML::SAX::Parser.new(WikiExtract.new)

# Send XML to the parser
parser.parse(wiki_xml)

# Close Wikipedia Pages XML
wiki_xml.close

#!/usr/bin/env ruby
# encoding: utf-8
require 'optparse'
require File.dirname(File.dirname(__FILE__)) + '/environment.rb'
config_file = File.join(File.dirname(File.dirname(__FILE__)), 'config.yml')
raise "Config file not found" unless File.exists?(config_file)

options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: app.rb [options]"

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end

  opts.on("-k", "--keyword [KEYWORD]", String, "Produce first page for page by keyword") do |keyword|
    options[:keyword] = keyword
  end

  opts.on("-y", "--year [YEAR]", Integer, "Limit first pages to year") do |year|
    options[:year] = year
  end

  opts.on("-s", "--keywords", "Produce all first page documents for each keyword") do
    options[:all_keywords] = true
  end

  opts.on("-a", "--all", "Produce all first pages for all documents") do
    options[:all] = true
  end

end.parse!

$pdf_dir = File.join(File.dirname(File.dirname(__FILE__)), 'pdfs')
$year = !options[:year].nil? ? options[:year] : Time.new.year
$mt = MuseumTracker.new({ config_file: config_file })
$accepted_keywords = ["botany", "mineralogy", "other", "palaeontology", "zoology"]

def make_stamp(template, file_name)
  `pdftk #{$pdf_dir}/first_page/#{file_name} stamp #{$pdf_dir}/stamped/stamp_templates/#{template}_stamp.pdf output #{$pdf_dir}/stamped/#{file_name}`
  FileUtils.mv "#{$pdf_dir}/stamped/#{file_name}", "#{$pdf_dir}/first_page/#{file_name}"
end

def make_compilation(bundle, compiled_name)
  bundle.each do |citation|
    pdf = File.join($pdf_dir, "#{citation[:md5]}.pdf")
    file_name = File.basename(pdf)

    if File.exists?(pdf)
      `pdftk #{pdf} cat 1 output #{$pdf_dir}/first_page/#{file_name}`
      if $mt.specimens.where(citation_id: citation[:id]).count > 0
        make_stamp("cited_specimens", file_name)
      end
      if !citation[:license].nil?
        make_stamp("open_access", file_name)
      end
      if citation[:possible_authorship]
        make_stamp("authored", file_name)
      end
      if !citation[:keywords].nil?
        citation[:keywords].split(",").each do |k|
          keyword = k.strip
          if $accepted_keywords.include?(keyword)
            make_stamp(keyword, file_name)
          end
        end
      end
    end
    puts citation[:id]
  end

  `pdftk #{$pdf_dir}/first_page/*.pdf cat output #{$pdf_dir}/#{compiled_name}.pdf`

  FileUtils.rm_rf Dir.glob("#{$pdf_dir}/first_page/*.pdf")
end

if options[:all]
  bundle = $mt.database["SELECT * from citations WHERE year = #{$year}"]
  make_compilation(bundle, "all_first_pages")
elsif options[:all_keywords]
  $accepted_keywords.each do |keyword|
    puts keyword.green
    bundle = $mt.database["SELECT * FROM citations WHERE MATCH (keywords) AGAINST ('+#{keyword}' IN BOOLEAN MODE) AND year = #{$year} ORDER BY id"]
    make_compilation(bundle, "#{keyword}_first_pages")
  end
elsif options[:keyword]
  bundle = $mt.database["SELECT * FROM citations WHERE MATCH (keywords) AGAINST ('+#{options[:keyword]}' IN BOOLEAN MODE) AND year = #{$year} ORDER BY id"]
  make_compilation(bundle, "#{options[:keyword]}_first_pages")
end
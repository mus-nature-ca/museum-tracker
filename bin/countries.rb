#!/usr/bin/env ruby
# encoding: utf-8
require 'optparse'
require File.dirname(File.dirname(__FILE__)) + '/environment.rb'
$config_file = File.join(File.dirname(File.dirname(__FILE__)), 'config.yml')
raise "Config file not found" unless File.exists?($config_file)

options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: countries.rb [options]"

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
  
  opts.on("-y", "--year [YEAR]", Integer, "Limit counts to a particular year") do |year|
    options[:year] = year
  end

end

def make_webpage(year = Time.new.year)
  root = File.dirname(File.dirname(__FILE__))
  template = File.join(root, 'template', "country-summary.slim")
  web_page = File.join(root, "country-summary-#{year}.html")
  html = Slim::Template.new(template).render(Object.new, collect_data(year))
  File.open(web_page, 'w') { |file| file.write(html) }
  html
end

def collect_data(year)
  mt = MuseumTracker.new({ config_file: $config_file })
  data = {
    generation_time: Time.now.strftime('%Y-%m-%d %H:%M:%S'),
    entries: []
  }
  raw_countries = mt.database["SELECT DISTINCT countries FROM citations WHERE countries IS NOT NULL AND year = #{mt.database.literal(year)}"]
  all_countries = Set.new
  raw_countries.all.each do |country|
    all_countries.merge(country[:countries].split(",").map(&:strip))
  end
  puts "#{year}".yellow
  all_countries.sort.each do |ct|
    country = ct.gsub(/\s+?of\s+?/, " ").split(" ").join(" +").prepend("+")
    records = mt.database["SELECT id FROM citations WHERE MATCH (countries) AGAINST (#{mt.database.literal(country)} IN BOOLEAN MODE) AND year = #{mt.database.literal(year)}"]
    puts "#{ct}: #{records.count}".green
    data[:entries] << { country: ct, count: records.count }
  end
  data
end

begin
  optparse.parse!
  year = !options[:year].nil? ? options[:year] : 2018
  make_webpage(year)
rescue
  puts $!.to_s
  puts optparse
  exit 
end
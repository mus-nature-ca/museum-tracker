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

  opts.on("-c", "--country [COUNTRY]", String, "Count of papers tagged with a particular country") do |country|
    options[:country] = country
  end

  opts.on("-a", "--all", "Counts for all countries") do
    options[:all] = true
  end
  
  opts.on("-y", "--year [YEAR]", Integer, "Limit counts to a particular year") do |year|
    options[:year] = year
  end

end

begin
  optparse.parse!
  mt = MuseumTracker.new({ config_file: config_file })

  #get all countries

  where_year = nil
  if options[:year]
    where_year = " AND year = #{mt.database.literal(options[:year])}"
  end

  if options[:country]
    country = options[:country].gsub(/\s+?of\s+?/, " ").split(" ").join(" +").prepend("+")
    records = mt.database["SELECT id FROM citations WHERE MATCH (countries) AGAINST (#{mt.database.literal(country)} IN BOOLEAN MODE)#{where_year}"]
    puts "Authors #{options[:country]}#{where_year}: #{records.count}".green
  elsif options[:all]
    raw_countries = mt.database["SELECT DISTINCT countries FROM citations WHERE countries IS NOT NULL"]
    all_countries = Set.new
    raw_countries.all.each do |country|
      all_countries.merge(country[:countries].split(","))
    end
    puts "#{options[:year]}".yellow if options[:year]
    all_countries.sort.each do |ct|
      country = ct.gsub(/\s+?of\s+?/, " ").split(" ").join(" +").prepend("+")
      records = mt.database["SELECT id FROM citations WHERE MATCH (countries) AGAINST (#{mt.database.literal(country)} IN BOOLEAN MODE)#{where_year}"]
      puts "Authors from #{ct}: #{records.count}".green
    end
  end

rescue
  puts $!.to_s
  puts optparse
  exit 
end
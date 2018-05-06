#!/usr/bin/env ruby
# encoding: utf-8
require 'optparse'
require File.dirname(File.dirname(__FILE__)) + '/environment.rb'
config_file = File.join(File.dirname(File.dirname(__FILE__)), 'config.yml')

options = {}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: app.rb [options]"

  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end

  opts.on("-e", "--environment [ENVIRONMENT]", String, "Include environment, defaults to development") do |env|
    options[:environment] = env
  end

  opts.on("-c", "--config [FILE]", String, "Include a full path to the config.yml file") do |config|
    options[:config] = config
  end

  opts.on("-t", "--trash", "Delete Gmail messages when read") do
    options[:trash] = true
  end

  opts.on("-o", "--output", "Make a csv and put in public directory") do
    options[:csv] = true
  end

  opts.on("-x", "--excel", "Make an Excle file and put in public directory") do
    options[:excel] = true
  end
  
  opts.on("-d", "--doi [DOI]", String, "Include a DOI to a paper") do |doi|
    options[:doi] = doi
  end

  opts.on("-f", "--file [FILE]", String, "Include a full path to a PDF file") do |file|
    options[:file] = file
  end

  opts.on("-u", "--url [URL]", String, "Include a URL to a PDF file") do |url|
    options[:url] = url
  end

end

begin
  optparse.parse!
  config_file = options[:config] if options[:config]
  ENV["ENVIRONMENT"] = options[:environment].nil? ? "development" : options[:environment]
  raise "Config file not found" unless File.exists?(config_file)

  mt = MuseumTracker.new({ config_file: config_file, delete_messages: options[:trash] })

  if options[:file]
    mt.insert_file(options[:file], options[:doi])
  elsif options[:url]
    mt.insert_url(options[:url], options[:doi])
    mt.queue_and_run
    mt.send_scihub_requests
    mt.send_crossref_requests
  elsif options[:doi]
    mt.insert_doi(options[:doi])
    puts "Gathering PDFs...".yellow
    mt.send_scihub_requests
    mt.send_crossref_requests
  else
    citations = mt.new_gmail_citations
    if citations.count > 0
      puts "#{citations.count} citations found. Processing...".green
      mt.queue_and_run
      puts "Gathering PDFs...".yellow
      mt.send_scihub_requests
      mt.send_crossref_requests
    end
  end

  puts "Extracting entities...".yellow
  mt.extract_entities
  puts "Updating metadata...".yellow
  mt.update_metadata

  mt.write_webpage

  if options[:csv]
    mt.write_csv
  end

  if options[:excel]
    mt.write_xlsx
  end

  puts "Done".green

rescue
  puts $!.to_s
  puts optparse
  exit 
end
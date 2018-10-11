#!/usr/bin/env ruby
# encoding: utf-8
require 'optparse'
require File.dirname(File.dirname(__FILE__)) + '/environment.rb'
config_file = File.join(File.dirname(File.dirname(__FILE__)), 'config.yml')
raise "Config file not found" unless File.exists?(config_file)

mt = MuseumTracker.new({ config_file: config_file })

file = "/Users/dshorthouse/Desktop/science_review_countries.csv"

CSV.foreach(file, :headers => true) do |row|
  mt.citations.where(id: row.first[1].to_i).update({countries: row["countries"]})
end

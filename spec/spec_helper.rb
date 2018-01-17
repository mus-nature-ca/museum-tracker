require "rspec"
require_relative "../environment.rb"

ENV["ENVIRONMENT"] = "test"

root = File.dirname(File.dirname(__FILE__))
CONFIG_FILE =  File.join(root, 'config.yml')
REGEX_FILE = File.join(root, 'regex.yml')
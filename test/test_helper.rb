$:.unshift(File.dirname(__FILE__) + '/../lib')
plugin_test_dir = File.dirname(__FILE__)
RAILS_ROOT = plugin_test_dir

require 'rubygems'
require 'mongo_mapper'
require 'test/unit'
require 'multi_rails_init'
require 'test_help'

require plugin_test_dir + '/../init.rb'

TestCaseClass = ActiveSupport::TestCase rescue Test::Unit::TestCase

MongoMapper.database = "mongo_nested_set_test"

Dir["#{plugin_test_dir}/fixtures/*.rb"].each {|file| require file }

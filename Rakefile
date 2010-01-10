begin
  require 'jeweler'
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
  exit 1
end
require 'rake/testtask'
require 'rake/rdoctask'
require 'rcov/rcovtask'
require "load_multi_rails_rake_tasks" 

Jeweler::Tasks.new do |s|
  s.name = "mongo_nested_set"
  s.summary = "Port of awesome_nested_set for MongoMapper"
  s.description = s.summary
  s.email = "fauxparse@gmail.com"
  s.homepage = "http://github.com/fauxparse/mongo_nested_set"
  s.authors = ["Matt Powell", "Brandon Keepers", "Daniel Morrison"]
  s.add_dependency "mongo_mapper", ['>= 0.6.10']
  s.has_rdoc = true
  s.extra_rdoc_files = [ "README.rdoc"]
  s.rdoc_options = ["--main", "README.rdoc", "--inline-source", "--line-numbers"]
  s.test_files = Dir['test/**/*.{yml,rb}']
end
Jeweler::GemcutterTasks.new
 
desc 'Default: run unit tests.'
task :default => :test

desc 'Test the mongo_nested_set plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs += ['lib', 'test']
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Generate documentation for the awesome_nested_set plugin.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.title    = 'MongoNestedSet'
  rdoc.options << '--line-numbers' << '--inline-source'
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

namespace :test do
  desc "just rcov minus html output"
  Rcov::RcovTask.new(:coverage) do |t|
    t.libs << 'test'
    t.test_files = FileList['test/**/*_test.rb']
    t.output_dir = 'coverage'
    t.verbose = true
    t.rcov_opts = %w(--exclude test,/usr/lib/ruby,/Library/Ruby,lib/mongo_nested_set/named_scope.rb --sort coverage)
  end
end
load 'deploy'
# Uncomment if you are using Rails' asset pipeline
    # load 'deploy/assets'
env = ENV['RUBBER_ENV'] ||= (ENV['RAILS_ENV'] || 'production')
root = File.expand_path(File.dirname(__FILE__) + '/../salamanca')

# this tries first as a rails plugin then as a gem
require 'rubber'

Rubber::initialize(root, env)
require 'rubber/capistrano'

load 'config/deploy' # remove this line to skip loading any of the default tasks
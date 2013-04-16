FileUtils.mkdir_p 'log' unless File.exists?('log')
log = File.new("logs/sinatra.log", "a+")
$stdout.reopen(log)
$stderr.reopen(log)

require File.dirname(__FILE__) + "/app"

run Application
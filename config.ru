FileUtils.mkdir_p '/home/ubuntu/logs' unless File.exists?('/home/ubuntu/logs')
log = File.new("/home/ubuntu/logs/sinatra.log", "a+")
$stdout.reopen(log)
$stderr.reopen(log)

require File.dirname(__FILE__) + "/app"

run Application
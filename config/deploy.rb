#{}`ssh-add`
require "bundler/capistrano"

set :rails_env, Rubber.env

set :application, "tio"
#set :repository,  "git@bitbucket.org:xenda/salamanca-chat.git"
set :repository,  "git@github.com:xenda/salamanca-chat.git"
set :branch, "master"

set :ssh_options, { :forward_agent => true }
default_run_options[:pty] = true

#ssh_options[:keys] = [File.join(ENV["HOME"], ".ec2", "gsg-keypair")]
# set :scm, :git # You can set :scm explicitly or Capistrano will make an intelligent guess based on known version control directory names
# Or: `accurev`, `bzr`, `cvs`, `darcs`, `git`, `mercurial`, `perforce`, `subversion` or `none`
#default_run_options[:pty] = true
#RUBBER_ROOT = "../salamanca"

on :load do
  set :application, "tio"
  set :runner,      rubber_env.app_user
  set :deploy_to,   "/mnt/#{application}-#{Rubber.env}"
  set :copy_exclude, [".git/*", ".bundle/*", "log/*", ".rvmrc", ".rbenv-version"]
end

set :scm, :git

#set :deploy_via, :copy
ssh_options[:forward_agent] = true
set :ssh_options, { :forward_agent => true }
set :deploy_via, :remote_cache
# Easier to do system level config as root - probably should do it through
# sudo in the future.  We use ssh keys for access, so no passwd needed
set :user, 'root'
set :password, nil


namespace :deploy do
  rubber.allow_optional_tasks(self)
  tasks.values.each do |t|
    if t.options[:roles]
      task t.name, t.options, &t.body
    end
  end
end

namespace :deploy do
  namespace :assets do
    rubber.allow_optional_tasks(self)
    tasks.values.each do |t|
      if t.options[:roles]
        task t.name, t.options, &t.body
      end
    end
  end
end

# load in the deploy scripts installed by vulcanize for each rubber module
Dir["#{File.dirname(__FILE__)}/rubber/deploy-*.rb"].each do |deploy_file|
  load deploy_file
end

# capistrano's deploy:cleanup doesn't play well with FILTER
after "deploy", "cleanup"
after "deploy:migrations", "cleanup"
task :cleanup, :except => { :no_release => true } do
  count = fetch(:keep_releases, 5).to_i
  
  rsudo <<-CMD
    all=$(ls -x1 #{releases_path} | sort -n);
    keep=$(ls -x1 #{releases_path} | sort -n | tail -n #{count});
    remove=$(comm -23 <(echo -e "$all") <(echo -e "$keep"));
    for r in $remove; do rm -rf #{releases_path}/$r; done;
  CMD
end

if Rubber::Util.has_asset_pipeline?
  # load asset pipeline tasks, and reorder them to run after
  # rubber:config so that database.yml/etc has been generated
  load 'deploy/assets'
  callbacks[:after].delete_if {|c| c.source == "deploy:assets:precompile"}
  callbacks[:before].delete_if {|c| c.source == "deploy:assets:symlink"}
  before "deploy:assets:precompile", "deploy:assets:symlink"
  after "rubber:config", "deploy:assets:precompile"
end


# role :web, "your web-server here"                          # Your HTTP server, Apache/etc
# role :app, "your app-server here"                          # This may be the same as your `Web` server
# role :db,  "your primary db-server here", :primary => true # This is where Rails migrations will run
# role :db,  "your slave db-server here"

callbacks[:after].delete_if { |c| c.source == 'rubber:config' }

# if you want to clean up old releases on each deploy uncomment this:
# after "deploy:restart", "deploy:cleanup"

# if you're still using the script/reaper helper you will need
# these http://github.com/rails/irs_process_scripts

# If you are using Passenger mod_rails uncomment this:
# namespace :deploy do
#   task :start do ; end
#   task :stop do ; end
#   task :restart, :roles => :app, :except => { :no_release => true } do
#     run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
#   end
# end

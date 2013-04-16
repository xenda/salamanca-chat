# encoding: UTF-8
require 'sinatra'
require 'json'
require 'mysql2'
require 'sanitize'
require 'gabba'
require 'active_support/all'

include ActiveSupport::Inflector

require './helpers'
require './social_publisher'

class Application < Sinatra::Base
  # set :database, {
  #   host: 'localhost',
  #   username: 'root',
  #   database: 'salamanca_development',
  #   password: ''
  # }
  set :logging, true

  configure :production, :development do
    enable :logging

    Twitter.configure do |config|
      config.consumer_key = 'VoI33HOQC9cjcweMFhZO2g'
      config.consumer_secret = '5MGv6S4x3YxEBufmPlCw5KlB1xnHFY83x1c8tmIrA'
    end
  end

  set :database, {
    host: '192.168.161.239',
    username: 'stoptv',
    database: 'salamanca_production',
    password: 'stoptvSTOPTV2013'
  }

  post '/chat_messages' do
    content_type :json
    response['Access-Control-Allow-Origin'] = '*'

    client = Mysql2::Client.new(settings.database)

    now = Time.now.getutc

    comment = {
      video_id: client.escape(params[:comment][:video_id].to_s),
      user_id: client.escape(params[:comment][:user_id].to_s),
      content: client.escape(Sanitize.clean(params[:comment][:content].to_s)),
      created_at: now,
      updated_at: now,
      publish_on_twitter: client.escape(params[:comment][:publish_on_twitter].to_s),
      publish_on_facebook: client.escape(params[:comment][:publish_on_facebook].to_s)
    }

    publish_on = {
      twitter: (comment[:publish_on_twitter] == "true"),
      facebook: (comment[:publish_on_facebook] == "true")
    }

    as_chat_message = true

    client.query("INSERT INTO comments (video_id, user_id, comment_type, content, created_at, updated_at, publish_on_twitter, publish_on_facebook) VALUES (#{comment[:video_id]}, #{comment[:user_id]}, 'chat', '#{comment[:content]}', '#{comment[:created_at]}', '#{comment[:updated_at]}', #{comment[:publish_on_twitter]}, #{comment[:publish_on_facebook]})")

    results = client.query("SELECT comments.id, comments.video_id, comments.content, comments.created_at, comments.videoshow_id, comments.user_id, comments.published_on_facebook_at, comments.published_on_twitter_at, users.avatar_file_name AS user_avatar_file_name, users.uid AS user_uid, users.first_name AS user_first_name FROM comments JOIN users ON comments.user_id = users.id WHERE comments.video_id = #{comment[:video_id]} AND comments.user_id = #{comment[:user_id]} AND comments.comment_type = 'chat' AND comments.created_at = '#{comment[:created_at].to_s.gsub(' UTC', '')}' AND comments.updated_at = '#{comment[:updated_at].to_s.gsub(' UTC', '')}' ORDER BY comments.created_at DESC LIMIT 1", symbolize_keys: true)

    messages = results_as_array(results)

    puts messages.inspect

    if messages.count > 0
      comment[:id] = messages.first[:id]
      comment[:published_on_twitter_at] = messages.first[:published_on_twitter_at]
      comment[:published_on_facebook_at] = messages.first[:published_on_facebook_at]

      client.query("INSERT INTO activities (author_id, action, source_id, source_type, target_id, target_type, receiver_id, created_at, updated_at) VALUES (#{comment[:user_id]}, 'create', #{comment[:id]}, 'Comment', #{comment[:video_id]}, 'Video', #{comment[:user_id]}, '#{comment[:created_at]}', '#{comment[:updated_at]}')")

      comment[:video] = find_video(client, comment[:video_id])
      comment[:user] = find_user(client, comment[:user_id])
      comment[:user][:social_accounts] = find_social_accounts(client, comment[:user_id])

      social_publisher = SocialPublisher.new(comment)
      social_publisher.db_client = client
      social_publisher.url = "http://stoptv.pe/videos/#{comment[:video_id]}-#{parameterize(comment[:video][:title])}"

      social_publisher.publish(publish_on, as_chat_message)

      gabba = Gabba::Gabba.new("UA-37832698-1", "http://stoptv.pe")
      gabba.event("Activities", "Create Comment", "Comentario en \"#{comment[:video][:title]}\"", comment[:id], true)
    end

    messages.to_a.to_json
  end

  get '/chat_messages' do
    content_type :json
    response['Access-Control-Allow-Origin'] = '*'

    begin
      client = Mysql2::Client.new(settings.database)

      video_id = client.escape(params[:video_id])
      user_id = client.escape(params[:user_id])
      since = Time.at(params[:since].to_i + 1).getutc

      results = client.query("SELECT comments.id, comments.video_id, comments.content, comments.created_at, comments.videoshow_id, comments.user_id, users.avatar_file_name AS user_avatar_file_name, users.uid AS user_uid, users.first_name AS user_first_name FROM comments JOIN users ON comments.user_id = users.id WHERE comments.comment_type = 'chat' AND comments.status != 'spam' AND comments.video_id = #{video_id} AND comments.user_id != #{user_id} AND comments.created_at >= '#{since}' ORDER BY created_at DESC", symbolize_keys: true)
      
      results = results_as_array(results)

      results.to_a.to_json
    rescue Exception => ex
     logger.info ex.message
     logger.info ex.backtrace
    end
  end
end
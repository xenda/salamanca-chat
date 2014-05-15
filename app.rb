require 'sinatra'
require 'json'
require 'mysql2'
require 'sanitize'
require 'gabba'
require 'active_support/all'
require 'pusher'

include ActiveSupport::Inflector

require './helpers'
require './social_publisher'

class Application < Sinatra::Base
  set :logging, true
  set :protection, :except => :json_csrf

  configure :production, :development do
    enable :logging

    Twitter.configure do |config|
      config.consumer_key = 'VoI33HOQC9cjcweMFhZO2g'
      config.consumer_secret = '5MGv6S4x3YxEBufmPlCw5KlB1xnHFY83x1c8tmIrA'
    end

    Pusher.app_id = '39474'
    Pusher.key = '21a2a768ce95c05bbd51'
    Pusher.secret = 'd5371c0ee79f81a48374'

  end

  set :database, {
    host: 'ec2-54-187-23-42.us-west-2.compute.amazonaws.com',
    username: 'mysqlstoptv',
    database: 'stoptv_production',
    password: 'P4s1ll0.9153#W4X'
  }

  before do
    if request.request_method == 'OPTIONS'
      response.headers["Access-Control-Allow-Origin"] = "*"
      response.headers["Access-Control-Allow-Methods"] = "POST, GET, OPTIONS"
      response.headers["Access-Control-Max-Age"] = "1000"
      response.headers["Access-Control-Allow-Headers"] = "*,x-requested-with"
      halt 200
    end
  end


  post '/votes' do
    content_type :json
    response['Access-Control-Allow-Origin'] = '*'

    client = Mysql2::Client.new(settings.database)

    now = Time.now.getutc

    video_id = client.escape(params[:video_id].to_s)
    current_user_id = client.escape(params[:user_id].to_s)

    vote = {
      votable_id: client.escape(params[:vote][:votable_id].to_s),
      votable_type: client.escape(params[:vote][:votable_type].to_s),
      user_id: client.escape(params[:user_id].to_s)
    }

    current_user = find_user(client, current_user_id)
    poll_item = find_poll_item(client, vote[:votable_id])
    poll = find_poll(client, poll_item[:poll_id])

    if has_voted(client, current_user, poll)
      { error: :already_voted }.to_json
    else
      client.query("INSERT INTO votes (votable_id, votable_type, user_id, created_at, updated_at) VALUES (#{vote[:votable_id]}, '#{vote[:votable_type]}', #{vote[:user_id]}, '#{now}', '#{now}')")

      poll_item = find_poll_item(client, vote[:votable_id])

      if poll_item
        votes_count = poll_item[:votes_count] + 1
        client.query("UPDATE poll_items SET votes_count = #{votes_count} WHERE id = #{poll_item[:id]}")
      end

      results = client.query("SELECT votable_id, votable_type, user_id FROM votes WHERE votable_id=#{vote[:votable_id]} AND votable_type='#{vote[:votable_type]}' AND user_id=#{vote[:user_id]} AND created_at='#{now.to_s.gsub(' UTC', '')}' AND updated_at='#{now.to_s.gsub(' UTC', '')}' LIMIT 1", symbolize_keys: true)

      if results.to_a.count == 1
        has_voted_poll = has_voted(client, current_user, poll)
        poll[:poll_items] = find_poll_items(client, poll[:id])

        poll[:poll_items].each do |poll_item|
          poll_item[:to_percentage] = to_percentage(poll, poll_item)
          poll_item[:has_chosen] = has_chosen(client, current_user, poll_item)
          poll_item[:voters] = find_voters(client, poll_item)
        end

        poll[:opened] = is_opened(poll)
      end


      client.close
      send_to_pusher(poll)
      poll.to_json
    end
  end

  def send_to_pusher(poll)
    #Get videoshow_id and video_id
    videoshow_id = poll[:videoshow_id]
    video_id = poll[:video_id]
    #Send To Pusher
    Pusher.trigger('on_air_video', 'create_poll', {'videoshow_id' => videoshow_id, 'video_id' => video_id})
  end

  post '/chat_messages' do
    content_type :json
    response['Access-Control-Allow-Origin'] = '*'

    client = Mysql2::Client.new(settings.database)

    now = Time.now.getutc

    comment = {
      video_id: client.escape(params[:comment][:video_id].to_s),
      user_id: client.escape(params[:comment][:user_id].to_s),
      content: client.escape(Sanitize.clean(params[:comment][:content].to_s.strip)),
      created_at: now,
      updated_at: now,
      publish_on_twitter: client.escape(params[:comment][:publish_on_twitter].to_s),
      publish_on_facebook: client.escape(params[:comment][:publish_on_facebook].to_s)
    }

    publish_on = {
      twitter: (comment[:publish_on_twitter] == "true"),
      facebook: (comment[:publish_on_facebook] == "true")
    }

    if comment[:content] == ''
      {error: 'Debes escribir un mensaje'}.to_json
    else
      as_chat_message = true

      begin
        comment_video = find_video(client, comment[:video_id])
        comment[:videoshow_id] = comment_video[:videoshow_id]
      rescue Exception => e
        comment[:videoshow_id] = nil
      end

      client.query("INSERT INTO comments (video_id, videoshow_id, user_id, comment_type, content, created_at, updated_at, publish_on_twitter, publish_on_facebook) VALUES (#{comment[:video_id]}, #{comment[:videoshow_id]}, #{comment[:user_id]}, 'chat', '#{comment[:content]}', '#{comment[:created_at]}', '#{comment[:updated_at]}', #{comment[:publish_on_twitter]}, #{comment[:publish_on_facebook]})")

      results = client.query("SELECT comments.id, comments.video_id, comments.content, comments.created_at, comments.videoshow_id, comments.user_id, comments.published_on_facebook_at, comments.published_on_twitter_at, users.nickname AS user_nickname, users.avatar_file_name AS user_avatar_file_name, users.social_avatar AS user_social_avatar, users.uid AS user_uid, users.first_name AS user_first_name FROM comments JOIN users ON comments.user_id = users.id WHERE comments.video_id = #{comment[:video_id]} AND comments.user_id = #{comment[:user_id]} AND comments.comment_type = 'chat' AND comments.created_at = '#{comment[:created_at].to_s.gsub(' UTC', '')}' AND comments.updated_at = '#{comment[:updated_at].to_s.gsub(' UTC', '')}' ORDER BY comments.created_at DESC LIMIT 1", symbolize_keys: true)

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
      
      client.close
      messages.to_a.to_json
    end
  end

  get '/chat_messages' do
    logger.info "Getting messages"
    puts "Returning messages"

    content_type :json
    response['Access-Control-Allow-Origin'] = '*'

    begin
      client = Mysql2::Client.new(settings.database)

      video_id = client.escape(params[:video_id] || "").to_i
      user_id = client.escape(params[:user_id] || "").to_i
      after = client.escape(params[:after] || "").to_i

      results = client.query("SELECT comments.id, comments.video_id, comments.content, comments.created_at, comments.videoshow_id, comments.user_id, users.nickname AS user_nickname, users.avatar_file_name AS user_avatar_file_name, users.social_avatar AS user_social_avatar, users.uid AS user_uid, users.first_name AS user_first_name FROM comments INNER JOIN users ON comments.user_id = users.id WHERE comments.comment_type = 'chat' AND comments.status != 'spam' AND comments.video_id = #{video_id} AND comments.user_id != #{user_id} AND comments.id > #{after} AND users.banned = false ORDER BY comments.created_at ASC", symbolize_keys: true)
      
      results = results_as_array(results)

      client.close

      results.to_a.to_json
    rescue Exception => ex
     logger.info ex.message
     logger.info ex.backtrace
    end
  end

  get '/previous_chat_messages' do
    content_type :json
    response['Access-Control-Allow-Origin'] = '*'

    begin
      client = Mysql2::Client.new(settings.database)

      video_id = client.escape(params[:video_id] || "").to_i
      before = client.escape(params[:before] || "").to_i

      results = client.query("SELECT comments.id, comments.video_id, comments.content, comments.created_at, comments.videoshow_id, comments.user_id, users.nickname AS user_nickname, users.avatar_file_name AS user_avatar_file_name, users.social_avatar AS user_social_avatar, users.uid AS user_uid, users.first_name AS user_first_name FROM comments INNER JOIN users ON comments.user_id = users.id WHERE comments.comment_type = 'chat' AND comments.status != 'spam' AND comments.video_id = #{video_id} AND comments.id < #{before} AND users.banned = false ORDER BY comments.created_at DESC LIMIT 50", symbolize_keys: true)
      
      results = results_as_array(results)

      client.close

      results.to_a.to_json
    rescue Exception => ex
     logger.info ex.message
     logger.info ex.backtrace
    end
  end

  get '/:id/chat_feed' do
    begin
    content_type :json

    response['Access-Control-Allow-Origin'] =  "*" #request.env['HTTP_ORIGIN']
    response['Access-Control-Allow-Methods'] = 'POST, GET, OPTIONS'
    response['Access-Control-Max-Age'] = '1000'
    response['Access-Control-Allow-Headers'] = '*,x-requested-with'
    
    client = Mysql2::Client.new(settings.database)

    video_id = client.escape(params[:id])

    conditions = ["comments.comment_type = 'chat'", "comments.video_id = #{video_id}", "users.banned = false"]

    conditions << "comments.id > #{client.escape(params[:after])}" if params[:after]
    conditions << "comments.id < #{client.escape(params[:before])}" if params[:before]

    results = client.query("SELECT comments.id, comments.video_id, comments.content, comments.created_at, comments.updated_at, comments.videoshow_id, comments.user_id, comments.publish_on_facebook, comments.publish_on_twitter, users.nickname AS user_nickname, users.avatar_file_name AS user_avatar_file_name, users.social_avatar AS user_social_avatar, users.uid AS user_uid, users.first_name AS user_first_name, users.last_name AS user_last_name FROM comments INNER JOIN users ON comments.user_id = users.id WHERE #{conditions.join(' AND ')} ORDER BY comments.created_at DESC LIMIT 30", symbolize_keys: true)

    messages = results_as_array(results, :big)
    
    feed = messages.map{ |chat_message|
      user = chat_message[:user]

      {
        :author_image => user[:avatar],
        :author_name => user[:full_name],
        :created_at => chat_message[:created_at].getlocal("-05:00"),
        :id => chat_message[:id],
        :message => chat_message[:content],
        :updated_at => chat_message[:updated_at].getlocal("-05:00"),
        :entry_type => 'CustomPost',
        :service_data => nil,
        :facebook? => (chat_message[:publish_on_facebook].to_s == "1"),
        :twitter? => (chat_message[:publish_on_twitter].to_s == "1"),
        :instagram? => false,
        :sms? => false,
        :email? => false,
        :likes => votes_count(client, chat_message[:id]),
        :retweets => nil,
        :service => 'custom'
      }
    }

    client.close
    content_type 'application/json'
    feed.to_json
    rescue Exception => ex
      logger.info ex.message
      logger.info ex.backtrace
    end
  end
end

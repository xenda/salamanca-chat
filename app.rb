# encoding: UTF-8
require 'sinatra'
require 'json'
require 'mysql2'
require 'sanitize'

def distance_of_time_in_words(from_time, to_time = Time.now, include_seconds = false, options = {})
  from_time = from_time.to_time if from_time.respond_to?(:to_time)
  to_time = to_time.to_time if to_time.respond_to?(:to_time)
  distance = (to_time.to_f - from_time.to_f).abs
  distance_in_minutes = (distance / 60.0).round
  distance_in_seconds = distance.round

  case distance_in_minutes
    when 0..1
      return distance_in_minutes == 0 ?
             'menos de 1 minuto' :
             "#{distance_in_minutes} minuto" unless include_seconds

      case distance_in_seconds
        when 0..4   then 'menos de 5 segundos'
        when 5..9   then 'menos de 10 segundos'
        when 10..19 then 'menos de 210 segundos'
        when 20..39 then 'medio minuto'
        when 40..59 then 'menos de 1 minuto'
        else             '1 minuto'
      end

    when 2..44           then "#{distance_in_minutes} minutos"
    when 45..89          then "cerca de 1 hora"
    when 90..1439        then "cerca de #{(distance_in_minutes.to_f / 60.0).round} horas"
    when 1440..2519      then "1 día"
    when 2520..43199     then "#{(distance_in_minutes.to_f / 1440.0).round} días"
    when 43200..86399    then "1 mes"
    when 86400..525599   then "#{(distance_in_minutes.to_f / 43200.0).round} meses"
    else
      fyear = from_time.year
      fyear += 1 if from_time.month >= 3
      tyear = to_time.year
      tyear -= 1 if to_time.month < 3
      leap_years = (fyear > tyear) ? 0 : (fyear..tyear).count{|x| Date.leap?(x)}
      minute_offset_for_leap_year = leap_years * 1440
      # Discount the leap year days when calculating year distance.
      # e.g. if there are 20 leap year days between 2 dates having the same day
      # and month then the based on 365 days calculation
      # the distance in years will come out to over 80 years when in written
      # english it would read better as about 80 years.
      minutes_with_offset         = distance_in_minutes - minute_offset_for_leap_year
      remainder                   = (minutes_with_offset % 525600)
      distance_in_years           = (minutes_with_offset / 525600)
      if remainder < 131400
        "#{distance_in_years} años"
      elsif remainder < 394200
        "más de #{distance_in_years} años"
      else
        "cerca de #{distance_in_years + 1} años"
      end
  end
end

def results_as_array(results)
  results.each do |row|
    if row["user_id"]
      row["created_at_as_timestamp"] = row["created_at"].to_i
      row["created_at_as_text"] = distance_of_time_in_words(row["created_at"] + row["created_at"].utc_offset)

      row["user"] = {}

      row["user"]["uid"] = row["user_uid"]
      row["user"]["first_name"] = row["user_first_name"]
      row["user"]["avatar"] = row["user_avatar_file_name"] ? row["user_avatar_file_name"] : "https://graph.facebook.com/#{row["user_uid"]}/picture"

      row.delete("user_uid")
      row.delete("user_first_name")
      row.delete("user_avatar_file_name")
    end
  end
end

class Application < Sinatra::Base
  set :database, {
    host: 'localhost',
    username: 'root',
    database: 'salamanca_development',
    password: ''
  }
  # set :database, {
  #   host: 'localhost',
  #   username: 'root',
  #   database: 'salamanca_production',
  #   password: 'stoptvSTOPTV2013'
  # }

  post '/chat_messages' do
    content_type :json
    response['Access-Control-Allow-Origin'] = '*'

    client = Mysql2::Client.new(settings.database)

    video_id = client.escape(params[:comment][:video_id])
    user_id = client.escape(params[:comment][:user_id])
    videoshow_id = client.escape(params[:comment][:videoshow_id])
    content = client.escape(Sanitize.clean(params[:comment][:content]))
    created_at = updated_at = Time.now.getutc

    client.query("INSERT INTO comments (video_id, user_id, videoshow_id, comment_type, content, created_at, updated_at) VALUES (#{video_id}, #{user_id}, #{videoshow_id}, 'chat', '#{content}', '#{created_at}', '#{updated_at}')")

    results = client.query("SELECT comments.id, comments.video_id, comments.content, comments.created_at, comments.videoshow_id, comments.user_id, users.avatar_file_name AS user_avatar_file_name, users.uid AS user_uid, users.first_name AS user_first_name FROM comments JOIN users ON comments.user_id = users.id WHERE comments.video_id = #{video_id} AND comments.user_id = #{user_id} AND comments.videoshow_id = #{videoshow_id} AND comments.comment_type = 'chat' AND comments.created_at = '#{created_at.to_s.gsub(' UTC', '')}' AND comments.updated_at = '#{updated_at.to_s.gsub(' UTC', '')}' ORDER BY comments.created_at DESC LIMIT 1")

    results = results_as_array(results)

    results.to_a.to_json
  end

  get '/chat_messages' do
    content_type :json
    response['Access-Control-Allow-Origin'] = '*'

    client = Mysql2::Client.new(settings.database)

    video_id = client.escape(params[:video_id])
    user_id = client.escape(params[:user_id])
    since = Time.at(params[:since].to_i + 1).getutc

    results = client.query("SELECT comments.id, comments.video_id, comments.content, comments.created_at, comments.videoshow_id, comments.user_id, users.avatar_file_name AS user_avatar_file_name, users.uid AS user_uid, users.first_name AS user_first_name FROM comments JOIN users ON comments.user_id = users.id WHERE comments.comment_type = 'chat' AND comments.status != 'spam' AND comments.video_id = #{video_id} AND comments.user_id != #{user_id} AND comments.created_at >= '#{since}' ORDER BY created_at DESC")
    
    results = results_as_array(results)

    results.to_a.to_json
  end
end
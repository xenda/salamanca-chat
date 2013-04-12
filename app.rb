require 'sinatra'
require 'json'

get '/chat_messages' do
  client = Mysql2::Client.new(host: 'localhost', username: 'root', database: 'salamanca_production', password: '')

  video_id = client.escape(params[:video_id])
  user_id = client.escape(params[:user_id])
  since = Time.at(params[:since].to_i + 1)

  results = client.query("SELECT * FROM comments WHERE comment_type = 'chat' AND video_id = #{video_id} AND (status != 'spam') AND (user_id != #{user_id}) AND (created_at >= '#{since}') ORDER BY created_at DESC")

  user_ids = results.map{ |row| row["user_id"] }.uniq.join(', ')

  users = client.query("SELECT id, avatar_file_name, first_name FROM users WHERE id IN (#{user_ids})").group_by{ |row| row["id"] }

  results.each do |row|
    row["user"] = users[row["user_id"]].try(:first)

    if row["user"]
      row["user"]["avatar"] = row["user"]["avatar_file_name"].nil? ? "https://graph.facebook.com/#{row["user"]["uid"]}/picture" : row["user"]["avatar_file_name"]
    end
  end

  results.to_json
end
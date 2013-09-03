# encoding: UTF-8
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

def avatar(id, user_avatar_file_name, style = :medium)
  id_as_path = id.to_s.rjust(9, '0').chars.each_slice(3).to_a.map{ |chars| chars.join() }.join('/')
  "https://s3.amazonaws.com/salamanca.herokuapp.com/users/avatars/#{id_as_path}/#{style}/#{user_avatar_file_name}"
end

def picture(user, style = :medium)
  size = ""

  case style
    when :medium
      size = "?width=100&height=100"
    when :big
      size = "?width=200&height=200"
  end
  
  if user[:user_social_avatar].to_s == "" || user[:social_avatar].to_s == ""
    "https://graph.facebook.com/#{user[:user_uid] || user[:uid]}/picture#{size}"
  else
    user[:user_social_avatar] || user[:social_avatar]
  end
end

def full_name(user)
  if user[:nickname].to_s == "" || user[:user_nickname].to_s == ""
    "#{user[:first_name] || user[:user_first_name]} #{user[:last_name] || user[:user_last_name]}".strip
  else
    user[:nickname] || user[:user_nickname]
  end
end

def results_as_array(results, avatar_style = :medium)
  results.each do |row|
    if row[:user_id]
      row[:created_at_as_timestamp] = row[:created_at].to_i
      row[:created_at_as_text] = distance_of_time_in_words(row[:created_at] + row[:created_at].utc_offset)

      row[:user] = {}

      row[:user][:uid] = row[:user_uid]
      row[:user][:id] = row[:user_id]
      row[:user][:first_name] = row[:user_first_name]
      row[:user][:last_name] = row[:user_last_name]
      row[:user][:full_name] = full_name(row)
      row[:user][:avatar] = row[:user_avatar_file_name] ? avatar(row[:user_id], row[:user_avatar_file_name], avatar_style) : picture(row, avatar_style)

      row.delete(:user_uid)
      row.delete(:user_first_name)
      row.delete(:user_avatar_file_name)
      row.delete(:user_social_avatar)
      row.delete(:user_nickname)
    end
  end
end

def find_user(client, user_id)
  results = client.query("SELECT id, first_name, last_name, provider, uid, avatar_file_name, social_avatar, nickname FROM users WHERE id = #{user_id.to_i} LIMIT 1", symbolize_keys: true)

  user = results.to_a.first
  user[:full_name] = full_name(user)
  user[:avatar] = user[:avatar_file_name] ? avatar(user[:id], user[:avatar_file_name]) : picture(user)

  user
end

def find_video(client, video_id)
  results = client.query("SELECT id, title FROM videos WHERE id = #{video_id.to_i} LIMIT 1", symbolize_keys: true)

  results.to_a.first
end

def find_social_accounts(client, user_id)
  results = client.query("SELECT id, provider, uid, auth_token, auth_secret FROM social_accounts WHERE user_id = #{user_id.to_i}", symbolize_keys: true)

  results.to_a
end

def votes_count(client, comment_id)
  results = client.query("SELECT COUNT(id) AS votes_count FROM votes WHERE votable_id = #{comment_id} AND votable_type = 'Comment'", symbolize_keys: true).first

  results[:votes_count]
end

def find_poll_item(client, poll_item_id)
  results = client.query("SELECT id, poll_id, title, votes_count FROM poll_items WHERE id = #{poll_item_id} LIMIT 1", symbolize_keys: true)

  results.to_a.first
end

def find_poll(client, poll_id)
  results = client.query("SELECT id, title, video_id, videoshow_id, closed FROM polls WHERE id = #{poll_id} LIMIT 1", symbolize_keys: true)

  results.to_a.first
end

def find_poll_items(client, poll_id)
  results = client.query("SELECT id, poll_id, title, votes_count FROM poll_items WHERE poll_id = #{poll_id}", symbolize_keys: true)

  results.to_a
end

def has_voted(client, user, poll)
  poll_item_ids = find_poll_items(client, poll[:id]).map { |poll_item| poll_item[:id] }

  results = client.query("SELECT COUNT(id) AS votes_count FROM votes WHERE votable_id IN (#{poll_item_ids.join(',')}) AND votable_type = 'PollItem' AND user_id = #{user[:id]}", symbolize_keys: true).first

  results[:votes_count] > 0
end

def is_opened(poll)
  poll[:closed] == 0
end

def to_percentage(poll, poll_item, total = 100.0, unit = '%')
  if total_votes(poll) > 0
    ratio = (poll_item[:votes_count].to_f / total_votes(poll).to_f)
  else
    ratio = 0.0
  end

  "#{(ratio*total).round(0)}#{unit}"
end

def total_votes(poll)
  poll[:poll_items].sum{ |item| item[:votes_count].to_f }
end

def has_chosen(client, user, poll_item)
  results = client.query("SELECT COUNT(id) AS votes_count FROM votes WHERE votable_id = #{poll_item[:id]} AND votable_type = 'PollItem' AND user_id = #{user[:id]}", symbolize_keys: true).first

  results[:votes_count] > 0
end

def find_voters(client, poll_item)
  results = client.query("SELECT votes.user_id, users.avatar_file_name AS user_avatar_file_name, users.social_avatar AS user_social_avatar, users.nickname AS user_nickname, users.uid AS user_uid, users.first_name AS user_first_name FROM votes JOIN users ON votes.user_id = users.id WHERE votes.votable_id = #{poll_item[:id]} AND votes.votable_type = 'PollItem' LIMIT 2", symbolize_keys: true)

  results.each do |row|
    if row[:user_id]
      row[:user] = {}

      row[:user][:uid] = row[:user_uid]
      row[:user][:id] = row[:user_id]
      row[:user][:first_name] = row[:user_first_name]
      row[:user][:last_name] = row[:user_last_name]
      row[:user][:full_name] = full_name(row)
      row[:user][:avatar] = row[:user_avatar_file_name] ? avatar(row[:user_id], row[:user_avatar_file_name]) : picture(row)

      row.delete(:user_uid)
      row.delete(:user_first_name)
      row.delete(:user_avatar_file_name)
    end
  end
end
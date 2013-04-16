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

def results_as_array(results)
  results.each do |row|
    if row[:user_id]
      row[:created_at_as_timestamp] = row[:created_at].to_i
      row[:created_at_as_text] = distance_of_time_in_words(row[:created_at] + row[:created_at].utc_offset)

      row[:user] = {}

      row[:user][:uid] = row[:user_uid]
      row[:user][:first_name] = row[:user_first_name]
      row[:user][:avatar] = row[:user_avatar_file_name] ? row[:user_avatar_file_name] : "https://graph.facebook.com/#{row[:user_uid]}/picture"

      row.delete(:user_uid)
      row.delete(:user_first_name)
      row.delete(:user_avatar_file_name)
    end
  end
end

def find_user(client, user_id)
  results = client.query("SELECT id, first_name, last_name, provider, uid FROM users WHERE id = #{user_id.to_i} LIMIT 1", symbolize_keys: true)

  results.to_a.first
end

def find_video(client, video_id)
  results = client.query("SELECT id, title FROM videos WHERE id = #{video_id.to_i} LIMIT 1", symbolize_keys: true)

  results.to_a.first
end

def find_social_accounts(client, user_id)
  results = client.query("SELECT id, provider, uid, auth_token, auth_secret FROM social_accounts WHERE user_id = #{user_id.to_i}", symbolize_keys: true)

  results.to_a
end
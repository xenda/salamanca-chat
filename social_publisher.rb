# encoding: UTF-8
require 'mysql2'
require 'koala'
require 'twitter'
class SocialPublisher

  attr_accessor :url, :comment, :user, :video, :messages, :db_client

  MESSAGES = {
    :chat_video => "%{content}%{ellipsis} (%{url}) - @stoptvpe",
    :view_video => "He visto un episodio en STOPtv.pe",
    :comment_video => "Comenté en STOPtv.pe en \"%{video_title}\" %{url}",
    :participate_video => "He participado en un episodio de STOPTV.pe"
  }

  def initialize(comment = nil)
    self.comment = comment
    self.user = comment[:user]
    self.video = comment[:video]
    self.messages = SocialPublisher::MESSAGES
  end

  def publish(permissions, as_chat_message = false)
    self.user[:social_accounts].each do |social|
      if social[:auth_token].present?
        case social[:provider]
          when 'facebook'
            if permissions[:facebook] && self.comment[:published_on_facebook_at].nil?
              Thread.new {
                client = Koala::Facebook::API.new(social[:auth_token])

                if as_chat_message
                  facebook_message = self.comment[:content]
                else
                  facebook_message = "Comenté en un video de STOPtv.pe"
                end

                client.put_connections("me", "feed", {
                  :message => facebook_message,
                  :link => self.url,
                  :name => self.video[:title]
                })

                self.comment[:published_on_facebook_at] = Time.now.getutc
                self.db_client.query("UPDATE comments SET published_on_facebook_at = '#{self.comment[:published_on_facebook_at]}' WHERE id = #{self.comment[:id]}")
              }
            end
          when 'twitter'
            if permissions[:twitter] && self.comment[:published_on_twitter_at].nil?
              
              twitter_client = Twitter::Client.new({
                :oauth_token => social[:auth_token],
                :oauth_token_secret => social[:auth_secret]
              })

              if as_chat_message
                twitter_message = self.messages[:chat_video] % {
                  :content => self.comment[:content][0..120],
                  :ellipsis => ( (self.comment[:content].size > 120) ? '...' : '' ),
                  :url => self.url
                }
              else
                twitter_message = self.messages[:comment_video] % {
                :video_title => self.video[:title],
                :url => self.url
              }
              end

              Thread.new {
                twitter_client.update(twitter_message)
                
                self.comment[:published_on_twitter_at] = Time.now.getutc
                self.db_client.query("UPDATE comments SET published_on_twitter_at = '#{self.comment[:published_on_twitter_at]}' WHERE id = #{self.comment[:id]}")
              }
            end
        end
      end
    end
  end

end
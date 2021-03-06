# encoding: UTF-8
require 'digest/md5'

class Trip < ActiveRecord::Base
  belongs_to :user

  BOX_SIZE_IN_METERS = 30000

  COMPOSITION_COLLECTION = ['Alone', 'Couple', 'With friends', 'For Work']

  scope :from_friends_of, ->(user) { user.nil? ? none : where(:user_id => user.friends.pluck(:id) ) }
  scope :current, ->() { order('arriving ASC', 'leaving ASC').where('leaving >= ?', Date.today) }

  def self.find_near_between(current_user, latitude, longitude, arriving, leaving)

    trips_to_consider = ActiveRecord::Base.connection.execute %Q{

      SELECT trips.id, users.mood, users.time,
        earth_distance(ll_to_earth(#{ActiveRecord::Base.connection.quote(latitude)}, #{ActiveRecord::Base.connection.quote(longitude)}), ll_to_earth(trips.latitude, trips.longitude)) AS distance
      FROM trips
      INNER JOIN users ON users.id = trips.user_id
      WHERE
        (earth_box(ll_to_earth(#{ActiveRecord::Base.connection.quote(latitude)}, #{ActiveRecord::Base.connection.quote(longitude)}), #{BOX_SIZE_IN_METERS}) @> ll_to_earth(trips.latitude, trips.longitude))
        AND ((trips.arriving, (trips.leaving + interval '1 day')::date) OVERLAPS (#{ActiveRecord::Base.connection.quote(arriving)}, #{ActiveRecord::Base.connection.quote(leaving)}))
        AND leaving >= #{ActiveRecord::Base.connection.quote(Date.today)}
        AND trips.user_id != #{ActiveRecord::Base.connection.quote(current_user.id)}
        AND users.is_profile_completed IS TRUE
    }

    ids_to_properties = {}
    trips_to_consider.each {|r|

      if current_user.mood == 'Chic'
        if r['mood'] == 'Chic'
          match_mood = 1
        elsif r['mood'] == 'Cool'
          match_mood = 0.5
        else
          match_mood = 0
        end
      elsif current_user.mood == 'Hippie'
        if r['mood'] == 'Hippie'
          match_mood = 1
        elsif r['mood'] == 'Cool'
          match_mood = 0.5
        else
          match_mood = 0
        end
      else #current_user.mood == 'Cool'
        if r['mood'] == 'Cool'
          match_mood = 1
        elsif r['mood'] == 'Chic'
          match_mood = 0.5
        else
          match_mood = 0
        end
      end

      if current_user.time == 'All day'
        if r['time'] == 'All day'
          match_time = 1
        elsif r['time'] == 'Day'
          match_time = 0.5
        else
          match_time = 0
        end
      elsif current_user.time == 'Day'
        if r['time'] == 'Day'
          match_time = 1
        elsif r['time'] == 'All day'
          match_time = 0.5
        else
          match_time = 0
        end
      else # current_user.time == 'Night'
        if r['time'] == 'Night'
          match_time = 1
        elsif r['time'] == 'All day'
          match_time = 0.5
        else
          match_time = 0
        end
      end

      ids_to_properties[r['id'].to_i] = {
        :distance => r['distance'],
        :mood => r['mood'],
        :time => r['time'],
        :match_mood => match_mood,
        :match_time => match_time
      }

    }

    trips = Trip.where(:id => ids_to_properties.keys).to_a
    trips.sort_by! {|trip| [-ids_to_properties[trip.id][:match_mood], -ids_to_properties[trip.id][:match_time], ids_to_properties[trip.id][:distance], trip.arriving, trip.leaving] }

    return trips

  end

  def share_on_facebook

    params = {
              :city => self.city,
              :latitude => self.latitude,
              :longitude => self.longitude,
              :arriving => self.arriving.strftime("%d/%m/%Y"),
              :leaving => self.leaving.strftime("%d/%m/%Y")
            }.to_query

    url = "http://#{ENV['DOMAIN']}/search?#{params}"
    name = "#{self.city.split(',').first}, from #{self.arriving.strftime("%d/%m/%Y")} to #{self.leaving.strftime("%d/%m/%Y")}"
    caption = ENV['DOMAIN']
    description = self.message || ''
    picture = self.map_image_url(116,116)

    graph = Koala::Facebook::API.new(self.user.facebook_token, ENV['FACEBOOK_APP_SECRET'])
    begin
      graph.put_wall_post('I just added a trip on Travel-Meet.', {:link => url, :caption => caption, :name => name, :description => description, :picture => picture})
    rescue => e
      # we don't have permission
    end

  end

  def map_image_url(width, height)

    params = {
      width: width,
      height: height,
      v: Digest::MD5.hexdigest(self.cache_key + width.to_s + height.to_s)
    }

    "http://#{ENV['DOMAIN']}/trips/#{self.id}/image.png?#{params.to_query}"

  end

end





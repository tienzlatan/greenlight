# frozen_string_literal: true

# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/.
#
# Copyright (c) 2018 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# BigBlueButton is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with BigBlueButton; if not, see <http://www.gnu.org/licenses/>.

module Joiner
  extend ActiveSupport::Concern

  TEMPLATE_AVATARS = {
    none_or_loggedin_user_avatar: "/images/noavatar.gif",
    template_avatar_1: "/images/template_avatar_1.jpg",
    template_avatar_2: "/images/template_avatar_2.jpg",
    template_avatar_3: "/images/template_avatar_3.jpg",
    template_avatar_4: "/images/template_avatar_4.jpg",
    template_avatar_5: "/images/template_avatar_5.jpg",
    template_avatar_6: "/images/template_avatar_6.jpg",
    template_avatar_7: "/images/template_avatar_7.jpg",
    template_avatar_8: "/images/template_avatar_8.jpg",
    template_avatar_9: "/images/template_avatar_9.jpg",
    template_avatar_10: "/images/template_avatar_10.jpg",
    template_avatar_11: "/images/template_avatar_11.jpg",
    template_avatar_12: "/images/template_avatar_12.jpg",
    template_avatar_13: "/images/template_avatar_13.jpg",
    template_avatar_14: "/images/template_avatar_14.jpg",
    template_avatar_15: "/images/template_avatar_15.jpg",
    template_avatar_16: "/images/template_avatar_16.jpg",
    template_avatar_17: "/images/template_avatar_17.jpg",
    template_avatar_18: "/images/template_avatar_18.jpg",
    template_avatar_19: "/images/template_avatar_19.jpg",
    template_avatar_20: "/images/template_avatar_20.jpg",
    template_avatar_21: "/images/template_avatar_21.jpg",
    template_avatar_22: "/images/template_avatar_22.jpg",
    template_avatar_23: "/images/template_avatar_23.jpg",
    template_avatar_24: "/images/template_avatar_24.jpg",
  }

  # Displays the join room page to the user
  def show_user_join
    # Get users name
    @name = if current_user
      current_user.name
    elsif cookies.encrypted[:greenlight_name]
      cookies.encrypted[:greenlight_name]
    else
      ""
    end

    @search, @order_column, @order_direction, pub_recs =
      public_recordings(@room.bbb_id, params.permit(:search, :column, :direction), true)

    @pagy, @public_recordings = pagy_array(pub_recs)

    render :join
  end

  # create or update cookie to track the three most recent rooms a user joined
  def save_recent_rooms
    if current_user
      recently_joined_rooms = cookies.encrypted["#{current_user.uid}_recently_joined_rooms"].to_a
      cookies.encrypted["#{current_user.uid}_recently_joined_rooms"] =
        recently_joined_rooms.prepend(@room.id).uniq[0..2]
    end
  end

  def valid_avatar?(url)
    return false if URI::DEFAULT_PARSER.make_regexp(%w[http https]).match(url).nil?
    uri = URI(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true if uri.scheme == 'https'
    response = http.request_head(uri)
    return false if response.code != "200"
    response['content-length'].to_i < Rails.configuration.max_avatar_size
  end

  def join_room(opts)
    @room_settings = JSON.parse(@room[:room_settings])

    moderator_privileges = @room.owned_by?(current_user) || valid_moderator_access_code(session[:moderator_access_code])
    if room_running?(@room.bbb_id) || room_setting_with_config("anyoneCanStart") || moderator_privileges

      # Determine if the user needs to join as a moderator.
      opts[:user_is_moderator] = room_setting_with_config("joinModerator") || @shared_room || moderator_privileges
      opts[:record] = record_meeting
      opts[:require_moderator_approval] = room_setting_with_config("requireModeratorApproval")
      opts[:mute_on_start] = room_setting_with_config("muteOnStart")

      return redirect_to join_path(@room, current_user.name, opts, current_user.uid) if current_user

      join_name = params[:join_name] || params[@room.invite_path][:join_name]
      join_avatar = params[:join_avatar] || params[@room.invite_path][:join_avatar]

      logger.info "join_avatar: #{join_avatar}"

      opts[:avatarURL] = if join_avatar == "none_or_loggedin_user_avatar" && current_user # default selection
        current_user.image.present? && valid_avatar?(current_user.image) ? current_user.image : nil
      elsif join_avatar.start_with?("template_avatar") # template avatar selection
        if Rails.env == 'production'
          "#{request.protocol}#{request.host_with_port}/b#{TEMPLATE_AVATARS[join_avatar.to_sym]}"
        else
          "#{request.protocol}#{request.host_with_port}#{TEMPLATE_AVATARS[join_avatar.to_sym]}"
        end
      elsif join_avatar.start_with?("custom_avatar") # upload avatar selection
        if Rails.env == 'production'
          "#{request.protocol}#{request.host_with_port}/b/uploads/#{join_avatar.split('custom_avatar_')[1]}"
        else
          "#{request.protocol}#{request.host_with_port}/uploads/#{join_avatar.split('custom_avatar_')[1]}"
        end
      end

      logger.info "opts[:avatarURL]: #{opts[:avatarURL]}"

      redirect_to join_path(@room, join_name, opts, fetch_guest_id)
    else
      search_params = params[@room.invite_path] || params
      @search, @order_column, @order_direction, pub_recs =
        public_recordings(@room.bbb_id, search_params.permit(:search, :column, :direction), true)

      @pagy, @public_recordings = pagy_array(pub_recs)

      # They need to wait until the meeting begins.
      render :wait
    end
  end

  def incorrect_user_domain
    Rails.configuration.loadbalanced_configuration && @room.owner.provider != @user_domain
  end

  # Default, unconfigured meeting options.
  def default_meeting_options
    moderator_message = "#{I18n.t('invite_message')}<br> #{request.base_url + room_path(@room)}"
    moderator_message += "<br> #{I18n.t('modal.create_room.access_code')}: #{@room.access_code}" if @room.access_code.present?
    {
      user_is_moderator: false,
      meeting_logout_url: request.base_url + logout_room_path(@room),
      moderator_message: moderator_message,
      host: request.host,
      recording_default_visibility: @settings.get_value("Default Recording Visibility") == "public"
    }
  end

  private

  def fetch_guest_id
    return cookies[:guest_id] if cookies[:guest_id].present?

    guest_id = "gl-guest-#{SecureRandom.hex(12)}"

    cookies[:guest_id] = {
      value: guest_id,
      expires: 1.day.from_now
    }

    guest_id
  end
end

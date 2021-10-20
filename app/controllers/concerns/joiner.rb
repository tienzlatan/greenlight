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
    none: "/uploads/noavatar.gif",
    conan: "https://znews-photo.zadn.vn/w660/Uploaded/oplukaa/2020_08_13/Conan_thumb.jpg",
    mori: "https://game8.vn/media/201807/images/phai-chang-tham-tu-mori%20(6).jpg",
    ran: "https://cdn.tgdd.vn//GameApp/1358164//nhan-vat-mori-ran-4-800x525.jpg",
    kid: "https://i.ytimg.com/vi/LL74DmpWG40/hqdefault.jpg",
    hattori: "https://cdn.tgdd.vn//GameApp/-1//Hattori-Heiji-chang-tham-tu-lung-danh-mien-Tay-800x800.jpg",
    songoku: "https://st.quantrimang.com/photos/image/2019/03/13/HinhnenGoku-13.jpg",
    vegeta: "https://otakukart.com/wp-content/uploads/2021/08/super-dragon-ball-heroes-cosa-successo-vegeta-perche-non-goku-v3-509954.webp-1200x900.jpg",
    songohan: "https://conteudo.imguol.com.br/c/entretenimento/9c/2017/07/14/gohan-1500057808905_v2_1x1.jpg",
    chichi: "http://dragonballwiki.net/wp-content/uploads/2015/10/Dragon-Ball-Chi-Chi.jpg",
    bulma: "http://images5.fanpop.com/image/photos/31000000/Bulma-bulma-briefs-31006210-385-386.jpg"
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

  def join_room(opts, upload_file_url = "")
    @room_settings = JSON.parse(@room[:room_settings])

    moderator_privileges = @room.owned_by?(current_user) || valid_moderator_access_code(session[:moderator_access_code])
    if room_running?(@room.bbb_id) || room_setting_with_config("anyoneCanStart") || moderator_privileges

      # Determine if the user needs to join as a moderator.
      opts[:user_is_moderator] = room_setting_with_config("joinModerator") || @shared_room || moderator_privileges
      opts[:record] = record_meeting
      opts[:require_moderator_approval] = room_setting_with_config("requireModeratorApproval")
      opts[:mute_on_start] = room_setting_with_config("muteOnStart")

      if current_user
        opts[:avatarURL] = current_user.image if current_user.image.present? && valid_avatar?(current_user.image)

        redirect_to join_path(@room, current_user.name, opts, current_user.uid)
      else
        join_name = params[:join_name] || params[@room.invite_path][:join_name]
        join_template_avatar = params[:join_avatar] || params[@room.invite_path][:join_avatar]
        opts[:avatarURL] = if upload_file_url.length > 0
          upload_file_url
        else
          join_template_avatar && join_template_avatar != 'none' ? TEMPLATE_AVATARS[join_template_avatar.to_sym] : nil
        end

        redirect_to join_path(@room, join_name, opts, fetch_guest_id)
      end
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

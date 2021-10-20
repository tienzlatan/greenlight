class UploadsController < ApplicationController
  skip_before_action :verify_authenticity_token

  # POST /api/v1/uploads
  def upload_avatar
    # Saving file
    unless params[:avatar].blank?
      uploaded_file = params[:avatar]
      if uploaded_file.content_type.include? "image/"
        uploaded_file_custom_name = "#{DateTime.now.strftime('%Q')}-#{uploaded_file.original_filename}"
        logger.info "uploaded_file_custom_name: #{uploaded_file_custom_name}"

        origin = Magick::Image.from_blob(uploaded_file.read).first
        thumb = origin.resize!(100, 100)
        thumb.composite(origin, Magick::CenterGravity,
          Magick::CopyCompositeOp).write(Rails.root.join('public', 'uploads', uploaded_file_custom_name))

        return respond_to do |format|
          format.json { render json: { avatar_url: "/uploads/#{uploaded_file_custom_name}" }, status: :ok }
        end
      else
        return respond_to do |format|
          format.json { render json: { message: "Only image allowed. Please try again." }, status: :bad_request }
        end
      end
    end
    respond_to do |format|
      format.json { render json: { message: "Upload at least one image" }, status: :bad_request }
    end
  end
end

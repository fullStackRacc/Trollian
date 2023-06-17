# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  include Localized
  include UserTrackingConcern
  include SessionTrackingConcern
  include CacheConcern
  include DomainControlHelper

  helper_method :current_account
  helper_method :current_session
  helper_method :current_theme
  helper_method :single_user_mode?
  helper_method :use_seamless_external_login?
  helper_method :whitelist_mode?
  helper_method :current_emoji_size_simple
  helper_method :current_emoji_size_detailed
  helper_method :current_emoji_size_name
  helper_method :current_bbcode_spin
  helper_method :current_bbcode_flip
  helper_method :current_bbcode_size
  helper_method :current_bbcode_color
  helper_method :current_bbcode_pulse
  helper_method :current_bbcode_large
  helper_method :current_bbcode_colorhex
  helper_method :current_bbcode_quote
  helper_method :current_bbcode_code
  helper_method :current_bbcode_center
  helper_method :current_bbcode_right
  helper_method :current_bbcode_url
  helper_method :current_bbcode_caps
  helper_method :current_bbcode_lower
  helper_method :current_bbcode_kan
  helper_method :current_bbcode_comic
  helper_method :current_bbcode_doc
  helper_method :current_bbcode_strike
  helper_method :current_bbcode_hs
  helper_method :current_bbcode_cute2
  helper_method :current_bbcode_oa
  helper_method :current_bbcode_sc
  helper_method :current_bbcode_impact
  helper_method :current_bbcode_luci
  helper_method :current_bbcode_pap
  helper_method :current_bbcode_copap
  helper_method :current_bbcode_na
  helper_method :current_bbcode_nac
  helper_method :current_bbcode_cute
  helper_method :current_bbcode_i
  helper_method :current_bbcode_b
  helper_method :current_bbcode_u

  rescue_from ActionController::ParameterMissing, Paperclip::AdapterRegistry::NoHandlerError, with: :bad_request
  rescue_from Mastodon::NotPermittedError, with: :forbidden
  rescue_from ActionController::RoutingError, ActiveRecord::RecordNotFound, with: :not_found
  rescue_from ActionController::UnknownFormat, with: :not_acceptable
  rescue_from ActionController::InvalidAuthenticityToken, with: :unprocessable_entity
  rescue_from Mastodon::RateLimitExceededError, with: :too_many_requests

  rescue_from HTTP::Error, OpenSSL::SSL::SSLError, with: :internal_server_error
  rescue_from Mastodon::RaceConditionError, Stoplight::Error::RedLight, ActiveRecord::SerializationFailure, with: :service_unavailable

  rescue_from Seahorse::Client::NetworkingError do |e|
    Rails.logger.warn "Storage server error: #{e}"
    service_unavailable
  end

  before_action :store_current_location, except: :raise_not_found, unless: :devise_controller?
  before_action :require_functional!, if: :user_signed_in?

  skip_before_action :verify_authenticity_token, only: :raise_not_found

  def raise_not_found
    raise ActionController::RoutingError, "No route matches #{params[:unmatched_route]}"
  end

  private

  def authorized_fetch_mode?
    ENV['AUTHORIZED_FETCH'] == 'true' || Rails.configuration.x.whitelist_mode
  end

  def public_fetch_mode?
    !authorized_fetch_mode?
  end

  def store_current_location
    store_location_for(:user, request.url) unless [:json, :rss].include?(request.format&.to_sym)
  end

  def require_functional!
    redirect_to edit_user_registration_path unless current_user.functional?
  end

  def after_sign_out_path_for(_resource_or_scope)
    new_user_session_path
  end

  protected

  def truthy_param?(key)
    ActiveModel::Type::Boolean.new.cast(params[key])
  end

  def forbidden
    respond_with_error(403)
  end

  def not_found
    respond_with_error(404)
  end

  def gone
    respond_with_error(410)
  end

  def unprocessable_entity
    respond_with_error(422)
  end

  def not_acceptable
    respond_with_error(406)
  end

  def bad_request
    respond_with_error(400)
  end

  def internal_server_error
    respond_with_error(500)
  end

  def service_unavailable
    respond_with_error(503)
  end

  def too_many_requests
    respond_with_error(429)
  end

  def single_user_mode?
    @single_user_mode ||= Rails.configuration.x.single_user_mode && Account.where('id > 0').exists?
  end

  def use_seamless_external_login?
    Devise.pam_authentication || Devise.ldap_authentication
  end

  def current_account
    return @current_account if defined?(@current_account)

    @current_account = current_user&.account
  end

  def current_session
    return @current_session if defined?(@current_session)

    @current_session = SessionActivation.find_by(session_id: cookies.signed['_session_id']) if cookies.signed['_session_id'].present?
  end

  def current_theme
    return Setting.theme unless Themes.instance.names.include? current_user&.setting_theme
    current_user.setting_theme
  end

  def current_emoji_size_simple
    return current_user&.setting_emoji_size_simple
  end

  def current_emoji_size_detailed
    return current_user&.setting_emoji_size_detailed
  end

  def current_emoji_size_name
    return current_user&.setting_emoji_size_name
  end

  def current_bbcode_spin
    return current_user&.setting_bbcode_spin
  end

  def current_bbcode_pulse
    return current_user&.setting_bbcode_pulse
  end

  def current_bbcode_flip
    return current_user&.setting_bbcode_flip
  end

  def current_bbcode_color
    return current_user&.setting_bbcode_color
  end

  def current_bbcode_large
    return current_user&.setting_bbcode_large
  end

  def current_bbcode_size
    return current_user&.setting_bbcode_size
  end

  def current_bbcode_b
    return current_user&.setting_bbcode_b
  end

  def current_bbcode_i
    return current_user&.setting_bbcode_i
  end

  def current_bbcode_u
    return current_user&.setting_bbcode_u
  end

  def current_bbcode_strike
    return current_user&.setting_bbcode_strike
  end

  def current_bbcode_colorhex
    return current_user&.setting_bbcode_colorhex
  end

  def current_bbcode_quote
    return current_user&.setting_bbcode_quote
  end

  def current_bbcode_code
    return current_user&.setting_bbcode_code
  end

  def current_bbcode_center
    return current_user&.setting_bbcode_center
  end

  def current_bbcode_right
    return current_user&.setting_bbcode_right
  end

  def current_bbcode_url
    return current_user&.setting_bbcode_url
  end

  def current_bbcode_caps
    return current_user&.setting_bbcode_caps
  end

  def current_bbcode_lower
    return current_user&.setting_bbcode_lower
  end

  def current_bbcode_kan
    return current_user&.setting_bbcode_kan
  end

  def current_bbcode_comic
    return current_user&.setting_bbcode_comic
  end

  def current_bbcode_doc
    return current_user&.setting_bbcode_doc
  end

  def current_bbcode_hs
    return current_user&.setting_bbcode_hs
  end

  def current_bbcode_cute2
    return current_user&.setting_bbcode_cute2
  end

  def current_bbcode_oa
    return current_user&.setting_bbcode_oa
  end

  def current_bbcode_sc
    return current_user&.setting_bbcode_sc
  end

  def current_bbcode_impact
    return current_user&.setting_bbcode_impact
  end

  def current_bbcode_luci
    return current_user&.setting_bbcode_luci
  end

  def current_bbcode_pap
    return current_user&.setting_bbcode_pap
  end

  def current_bbcode_copap
    return current_user&.setting_bbcode_copap
  end

  def current_bbcode_na
    return current_user&.setting_bbcode_na
  end

  def current_bbcode_nac
    return current_user&.setting_bbcode_nac
  end

  def current_bbcode_cute
    return current_user&.setting_bbcode_cute
  end

  def respond_with_error(code)
    respond_to do |format|
      format.any  { render "errors/#{code}", layout: 'error', status: code, formats: [:html] }
      format.json { render json: { error: Rack::Utils::HTTP_STATUS_CODES[code] }, status: code }
    end
  end
end

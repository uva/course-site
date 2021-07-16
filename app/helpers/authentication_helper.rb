module AuthenticationHelper

	# decides if any of the auth methods is satisfied
	# may also be used by controller methods to make decisions
	def authenticated?
		return session[:user_login].present? || session[:user_id].present?
	end

	def logged_in?
		return authenticated? && current_user.persisted?
	end

	def current_user
		@current_user ||= (User.find_by(id: session[:user_id]) || User.new)
		Current.user = @current_user
	end

end

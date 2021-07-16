module Authentication

	include AuthenticationHelper

	# before_action to require at least a confirmed login, but not necessarily a user object
	def authenticate
		if not authenticated?
			# no cookie means no session was created
			redirect_to session_login_url
		end
	end

	# before_action to require a user to be logged in
	def authorize
		if session[:user_id].blank?
			# no cookie means no session was created
			redirect_to session_login_url
		elsif not current_user
			# user was logged in but hasn't registered yet
			redirect_to profile_url
		end
	end

	# role-based permissions
	def require_admin
		head :forbidden unless current_user.admin?
	end

	def require_senior
		head :forbidden unless current_user.head? or current_user.admin?
	end

	def require_staff
		head :forbidden unless current_user.admin? or current_user.assistant? or current_user.head?
	end

end

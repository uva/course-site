class SessionController < ApplicationController

	def new
		redirect_to authorization_uri
	end

	def callback
		if params[:error] == 'access_denied'
			redirect_to root_url and return
		end

		# authorization response
		code = params[:code]

		# handle local authentication
		client.authorization_code = code

		begin
			access_token = client.access_token!
		rescue Rack::OAuth2::Client::Error
			# this might happen when we return from the OP and we can't validate
			head(500) and return
		end

		token = access_token.access_token
		info = user_info(token)

		login = info.subject.downcase
		email = info.email
		name = info.name
		student_number = info.raw_attributes['schac_personal_unique_code'].try(:first)
		affiliation = info.raw_attributes['eduperson_affiliation']
		organization = info.raw_attributes['schac_home_organization']

		# redirect depending on the existence of a user profile
		if user = User.authenticate(login)
			session[:user_id] = user.id
			redirect_to root_url
		else
			u = User.create(
				login: login,
				name: name,
				mail: email,
				student_number: student_number,
				affiliation: affiliation,
				organization: organization,
				schedule: Schedule.first,
				role: :guest
			)
			# session[:user_login] = login
			session[:user_id] = u.id
			redirect_to root_url
		end
	end

	# login via generated token
	def tokenize
		if params[:token].present? && user = User.find_by(token: params[:token])
			session[:user_id] = params[:token]
		end
		redirect_to root_url
	end

	def destroy
		session.delete(:user_id)
		session.delete(:user_login)
		redirect_to root_url
	end

	private

	def client
		@client ||= OpenIDConnect::Client.new(
			identifier: ENV['OIDC_CLIENT_ID'],
			secret: ENV['OIDC_CLIENT_SECRET'],
			redirect_uri: ENV['OIDC_REDIRECT_URI'],
			host: ENV['OIDC_HOST'],
			authorization_endpoint: '/oidc/authorize',
			token_endpoint: '/oidc/token',
			userinfo_endpoint: '/oidc/userinfo'
		)
	end

	def authorization_uri
		state = SecureRandom.hex(16)
		nonce = SecureRandom.hex(16)

		client.authorization_uri(
			scope: scope,
			state: state,
			nonce: nonce
		)
	end

	def scope
		default_scope = %w(openid)

		# Add scope for social provider if social login is requested
		if params[:provider].present?
			default_scope << params[:provider]
		else
			default_scope
		end
	end

	def user_info(token)
		return nil unless token.present?

		access_token = OpenIDConnect::AccessToken.new(
			access_token: token,
			client: client
		)

		access_token.userinfo!
	end

end

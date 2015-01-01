require 'dropbox'

class ConfigController < ApplicationController

	before_filter CASClient::Frameworks::Rails::Filter
	before_filter :require_admin
	
	# show admins and assistants
	def admins
		@admins = Settings.admins.join("\n")
		@assistants = (Settings.assistants || []).join("\n")
	end
	
	# store new admins list
	def admins_save
		Settings.admins = params[:admins].split(/\r?\n/)
		redirect_to :back
	end
	
	# store new assistants list
	def assistants_save
		Settings.assistants = params[:assistants].split(/\r?\n/)
		redirect_to :back
	end
		
	# key entry page, also shows if already having a session
	def dropbox
		@dropbox_linked = Dropbox.connected?
	end
	
	def git_repo_save
		Settings.git_repo = params[:repo_url]
		redirect_to :back
	end

end
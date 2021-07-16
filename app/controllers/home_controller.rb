class HomeController < ApplicationController

	include NavigationHelper

	before_action :authorize, except: [ :homepage, :syllabus ]
	before_action :register_attendance, except: [ :homepage, :syllabus ]

	layout 'home'

	def homepage
		if User.admin.none?
			redirect_to welcome_path
		elsif logged_in? && alerts_for_current_schedule.any? || !(current_schedule && current_schedule.page || Page.find_by_slug(''))
			# show announcements page if no syllabus in repo or if there are ann to show at all
			redirect_to action: "announcements"
		else
			redirect_to action: "syllabus"
		end
	end

	def announcements
		@title = t(:announcements)
	end

	def syllabus
		# TODO
		@page = current_schedule && current_schedule.page || Page.find_by_slug('')
		raise ActionController::RoutingError.new('Not Found') if !@page
		@subpages = @page.subpages
		@title = t(:syllabus)
		render "page/index", layout: 'sidebar'
	end

end

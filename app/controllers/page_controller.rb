require 'dropbox'

class PageController < ApplicationController

	prepend_before_action CASClient::Frameworks::Rails::GatewayFilter, only: [ :homepage ]
	prepend_before_action CASClient::Frameworks::Rails::GatewayFilter, unless: :request_from_local_network?, except: [ :homepage ]
	prepend_before_action CASClient::Frameworks::Rails::Filter, if: :request_from_local_network?, except: [ :homepage ]

	before_action :register_attendance
	before_action :check_schedule
	
	def homepage
		if not Page.any?
			# no pages at all means probably not configured yet
			onboard
		elsif logged_in?
			announcements
		else
			syllabus
		end
	end
	
	def onboard
		if User.admin.any?
			# there's already an admin, go to config, will force login
			redirect_to config_path
		else
			# there's no admin yet, make current user admin
			redirect_to welcome_register_path
		end
	end
	
	def announcements
		@schedules = Schedule.all
		@student = User.includes(:hands, :notes).find(current_user.id)
		@grades = Grade.joins(:submit).includes(:submit).where('submits.user_id = ?', current_user.id).order('grades.created_at desc')
		@groups = Group.order(:name)
		@note = Note.new(student_id: @student.id)
	
		@items = []
		@items += @student.submits.where("submitted_at not null").to_a
		@items += @grades.to_a
		@items = @items.sort { |a,b| b.created_at <=> a.created_at }
		
		if current_user.senior? && current_user.schedule
			@groups = current_user.schedule.groups.order(:name)
			@psets = current_user.schedule.grades.finished.joins(:submit => :pset).group("psets.name").count
			@new_students = current_user.schedule.users.not_staff.registered
		end
	
		render "timeline/timeline"
	end
	
	def syllabus
		# the normal homepage is the page without a parent section
		@page = Page.where(:section_id => nil).first
	    raise ActionController::RoutingError.new('Not Found') if !@page
		render :index
	end
	
	def index
		# find section by url and bail out if not found
		@section = Section.where(:slug => params[:section]).first
	    raise ActionController::RoutingError.new('Not Found') if !@section
		
		# find page by url in section and bail out if not found
		@page = @section.pages.where(:slug => params[:page]).first		
	    raise ActionController::RoutingError.new('Not Found') if !@page
		
		if @page.pset && current_user.can_submit?
			@has_form = @page.pset.form
			@submitted = Submit.where(:user_id => current_user.id, :pset_id => @page.pset.id).count > 0
		end
		
		render :index
	end
	
	def submit
		if !session[:cas_user]
			redirect_to(:back, alert: 'Please login again before submitting.') and return
		end
		
		page = Page.find(params[:page_id])
		pset = page.pset

		if (pset.form || pset.files.any?) && !Dropbox.connected?
			redirect_to(:back, flash: { alert: "<b>There is a problem with submitting!</b> Warn your professor immediately and mention Dropbox.".html_safe }) and return
		end
		
		form_text = render_form_text(params[:a])

		# upload to dropbox
		if pset.form || pset.files
			begin
				upload_to_dropbox(session[:cas_user], current_user.name,
					Settings.submit_directory, pset.name, params[:notes], form_text, params[:f])
			rescue
				redirect_to(:back, flash: { alert: "<b>There was a problem uploading your submission! Please try again.</b> If the problem persists, contact your instructor.".html_safe }) and return
			end
		end

		# create submit record
		submit = Submit.where(:user_id => current_user.id, :pset_id => pset.id).first_or_initialize
		submit.submitted_at = Time.now
		submit.used_login = session[:cas_user]
		submit.url = params[:url]
		submit.submitted_files = params[:f].map { |file,info| info.original_filename } if params[:f]
		submit.save
	
		# success
		begin
			redirect_to :back
		rescue ActionController::RedirectBackError
			redirect_to :root
		end
	end
	
	private
	
	def check_schedule
		# if schedule has been updated, may find themselves without schedule
		logger.info "Checking schedule..."
		current_user.check_current_module
	end
	
	# writes hash with form contents to a plain text string
	def render_form_text(form)
		form_text = nil
		if form
			form_text = ""
			form.each do |key, value|
				form_text += "#{key}\n\n"
				form_text += "#{value}\n\n"
			end
		end
		return form_text
	end

	def upload_to_dropbox(user, name, course, item, notes, form, files)
		
		dropbox_client = Dropbox.client
		dropbox_root = ENV['DROPBOX_ROOT']
		
		# cache timestamp for folder name
		item_folder = item + "__" + Time.now.to_i.to_s

		# compose info.txt file contents
		info = "student_login_id = " + user
		info += ("\nname = " + name) if name
		info += "\n\n"
		info += notes if notes

		# upload the notes
		dropbox_client.upload(File.join("/", dropbox_root, course, user, item_folder, 'info.txt'), info) if notes
		
		# upload the form
		dropbox_client.upload(File.join("/", dropbox_root, course, user, item_folder, 'form.md'), form) if form
		
		# upload all posted files
		if files
			files.each do |filename, file|
				dropbox_client.upload(File.join("/", dropbox_root, course, user, item_folder, file.original_filename), file.read, autorename: true)
			end
		end

	end
	

end

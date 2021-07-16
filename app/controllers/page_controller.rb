class PageController < ApplicationController

	before_action :authorize, if: :request_from_local_network?
	before_action :register_attendance, if: :request_from_local_network?

	def index
		# find page by url and bail out if not found
		@page = Page.where(slug: params[:slug]).first
		raise ActionController::RoutingError.new('Not Found') if !@page

		@subpages = @page.subpages

		if @page.pset && current_user.can_submit?
			@has_form = @page.pset.form
			if @submit = Submit.where(:user_id => current_user.id, :pset_id => @page.pset.id).first
				@submitted_at = @submit.submitted_at
			end
			@allow_submit = @submit.blank? || @submit.may_be_resubmitted?
		end

		@title = @page.title
	end

end

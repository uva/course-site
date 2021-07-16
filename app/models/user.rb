class User < ApplicationRecord

	include Schedulizable
	include ChangeLogger

	# normal users
	belongs_to :group, optional: true
	delegate :name, to: :group, prefix: true, allow_nil: true
	scope :groupless,  -> { where(group_id: nil) }

	# permissions for heads/tas
	has_and_belongs_to_many :groups
	has_and_belongs_to_many :schedules
	has_many :students, through: :groups

	has_many :logins
	has_many :hands
	has_many :submits
	has_many :grades, through: :submits
	has_many :psets, through: :submits
	has_many :attendance_records
	has_many :notes, foreign_key: "student_id" # with counter cache
	has_many :authored_notes, class_name: "Note", foreign_key: "author_id"
	has_many :authored_grades, class_name: "Grade", foreign_key: "grader_id"

	has_secure_token

	enum role: [:guest, :student, :assistant, :head, :admin], _default: 'student'
	enum status: [:active, :registered, :inactive, :done], _default: 'registered', _prefix: 'status'

	scope :staff, -> { where(role: [:admin, :assistant, :head]) }
	scope :not_staff, -> { where.not(role: [:admin, :assistant, :head]) }

	scope :watching, -> { where(alarm: true) }

	scope :who_did_not_submit, ->(pset_id) do
		where("not exists (?)", Submit.where("submits.user_id = users.id").where(pset_id:pset_id))
	end

	serialize :progress, Hash

	def create_profile(params, login)
		# cancel this thing if registration is not open (but not if first user)
		raise unless User.none? || Schedule.none? || Schedule.default

		self.assign_attributes(params)
		# TODO ugly: default user has "empty" schedule, which we recognize here
		self.schedule = Schedule.default if self.schedule.blank? || !self.schedule.persisted?
		self.save!
		self.logins.create(login: login) unless self.logins.any?
	end

	def accessible_schedules
		if self.admin?
			# ensure admins have access to all schedules at all times by overriding
			Schedule.all
		else
			self.schedules
		end
	end

	# def self.find_by_login(login)
	# 	puts "HAH"
	# 	if user = super(login)
	# 		puts "HUH"
	# 		return user
	# 	elsif login = Login.find_by_login(login)
	# 		puts "HUH2"
	#
	# 		return login.user
	# 	end
	# end

	def self.authenticate(login)
		find_by_login(login)
	end

	def items(with_private=false)
		items = []
		# show all submits for psets that are _not_ a module
		items += submits.includes(:pset).where("submitted_at is not null").to_a
		items += grades.includes(:pset, :submit, :grader).showable.to_a
		# items += hands.includes(:assist).to_a if with_private
		items += notes.includes(:author).to_a if with_private
		items = items.sort { |a,b| b.sortable_date <=> a.sortable_date }
	end

	def initials
		name.split.map(&:first).join
	end

	def suspect_name
		first, *rest = *name.split
		first + " " + rest.map(&:first).join()
	end

	def submit(pset)
		submits.where(:pset_id => pset.id).first
	end

	def login_id
		return self.logins.first.try(:login) || self.token
	end

	def valid_profile?
		return self.persisted? && !self.name.blank?
	end

	def can_submit?
		return self.valid_profile?
	end

	def staff?
		admin? or assistant? or head?
	end

	def senior?
		admin? or head?
	end

	def stagnated?
		if self.last_submitted_at.blank?
			self.started_at.present? && self.started_at < 1.month.ago
		else
			self.last_submitted_at < 1.month.ago
		end
	end

	def final_grade
		'N/A'
	end

	def all_submits
		self.grades.group_by { |i| i.submit.pset.name }.each_with_object({}) { |(k,v),o| o[k] = v[0] }
	end

	def hands_overview
		hands.where(success:true).map do |h|
			if h.closed_at.present? && h.claimed_at.present?
				[h.id, h.claimed_at, (h.closed_at - h.claimed_at)/60, h.assist_name || ""]
			end
		end.compact
	end

	def take_attendance
		symbols = "▁▂▃▄▅▆▇█"
		user_attendance = self.attendance_records.group_by_day(:cutoff, default_value: 0, range: 7.days.ago...Time.now).count.values
		graph = user_attendance.map { |v| symbols[[v,7].min] }.join("")
		self.update_attribute(:attendance, graph)
	end

end

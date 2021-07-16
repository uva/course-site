class Grade < ApplicationRecord

	include Grading::GradeCalculator

	belongs_to :submit, touch: true

	has_one :user, through: :submit
	delegate :name, to: :user, prefix: true, allow_nil: true

	has_one :pset, through: :submit
	delegate :name, to: :pset, prefix: true, allow_nil: true

	belongs_to :grader, class_name: "User"
	delegate :name, to: :grader, prefix: true, allow_nil: true
	delegate :initials, to: :grader, prefix: true, allow_nil: true

	# this is an OpenStruct to make sure that subgrades can be referenced as a method
	# for use in the grade calculation formulae in grading.yml
	serialize :subgrades, OpenStruct

	scope :showable, -> { where(status: [Grade.statuses[:published], Grade.statuses[:exported]]) }

	enum status: [:unfinished, :finished, :published, :discussed, :exported]
	before_save :unpublicize_if_undone

	after_initialize do
		# this adds automatic grades to the subgrades quite aggressively
		if !self.persisted?
			# add any newly found autogrades to the subgrades as default
			self.submit.automatic_scores.each do |k,v|
				self.subgrades[k] = v if not self.subgrades[k].present?
			end
		end
	end

	before_validation do |grade|
		# assistants always take ownership of the grade when editing
		grade.grader = @current_user if grade.grader.blank? || (@current_user.present? && @current_user != grade.grader && grade.grader.senior?)
	end

	after_save do |grade|
		# set user to done if sufficient final grade has been entered
		if published? && sufficient? && Current.user.admin? && pset.is_final_grade?
			user.status_done!
		end
	end

	def sufficient?
		self.grade && self.grade >= 5.5
	end

	def reject!
		self.grade = 0
		published!
	end

	def sortable_date
		updated_at
	end

	def public?
		published? or discussed? or exported?
	end

	def last_graded
		updated_at && updated_at.to_formatted_s(:short) || "not yet"
	end

	def first_graded
		created_at && created_at.to_formatted_s(:short) || "not yet"
	end

	def subgrades=(val)
		# we would like this to be stored as an OpenStruct
		#return super if val.is_a? OpenStruct

		# take this opportunity to convert any stringified stuff to numbers
		val.each do |k,v|
			# get type from grading config
			begin
				grade_type = Settings['grading']['grades'][self.pset_name]['subgrades'][k]
			rescue
				grade_type = "integer"
			end

			case grade_type
			when "integer", "pass", "boolean"
				val[k] = v.to_i unless v == ""
			when "float"
				val[k] = v.sub(",", ".").to_f unless v == ""
			end
		end if val

		super OpenStruct.new val.to_h if val
	end

	def grade
		g = read_attribute(:grade)
		return nil if !g
		g = (g/10.0).round(1)
		return g
	end

	def calculated_grade
		g = read_attribute(:calculated_grade)
		return nil if !g
		g = (g/10.0).round(1)
		return g
	end

	def any_final_grade
		# this function prefers hard-coded grades but otherwise provides the calculated grade
		self.grade || self.calculated_grade
	end

	def grade=(new_grade)
		if new_grade.blank? # erases the grade
			return super(nil)
		elsif new_grade.class == String
			new_grade.sub!(/,/,'.')
			case self.pset.grade_type
			when 'float'
				super(10.0 * new_grade.to_f)
			else # integer, pass
				super(10.0 * new_grade.to_i)
			end
		else
			case self.pset.grade_type
			when 'float'
				super(10.0 * new_grade.to_f)
			else # integer, pass
				super(10.0 * new_grade.to_i)
			end
		end
	end

	def config
		grading_config = Settings['grading']
		return grading_config && grading_config['grades'] && grading_config['grades'][self.pset_name]
	end

	def format
		grading_config = config
		current_grade = any_final_grade
		return '--' if current_grade.blank?
		case grading_config && grading_config['type'] || 'float'
		when 'integer'
			return current_grade.to_i.to_s
		when 'pass'
			if current_grade.between?(-1,0)
				return (current_grade==-1 && 'v' || 'x')
			else
				return current_grade.to_s
			end
		else # float
			return current_grade.to_s
		end
	end

	private

	def unpublicize_if_undone
		self.status = Grade.statuses[:unfinished] if self.any_final_grade.blank?
		true
	end

end

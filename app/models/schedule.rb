class Schedule < ActiveRecord::Base
	
	#
	# A schedule is one particular time or way to do the course - there may be multiple
	#

	# A schedule defines a set of modules (ScheduleSpans) that students work through
	has_many :schedule_spans, dependent: :destroy
	belongs_to :current, class_name: "ScheduleSpan", foreign_key: "current_schedule_span_id"

	# A schedule can have grading groups defined
	has_many :groups, dependent: :destroy
	
	# These are the students in the schedule
	has_many :users
	has_many :grades, through: :users
	has_many :hands, through: :users
	
	# These are the staff that may have been assigned to grade this group
	has_and_belongs_to_many :graders, class_name: "User"

	def load(contents)
		# this method accepts the yaml contents of a schedule file

		# save the NAME of the current schedule item, to restore later
		backup_position = current.name if current
		
		# delete al items
		schedule_spans.delete_all
		
		# create all items
		contents.each do |name, items|
			span = schedule_spans.where(name: name).first_or_initialize
			span.content = items.to_yaml
			span.save
		end
		
		# restore 'current' item
		update_attribute(:current, backup_position && self.schedule_spans.find_by_name(backup_position))
	end
	
	def generate_groups(number)
		# delete old groups for this schedule
		self.groups.delete_all
		
		# create the requested number of groups
		for n in 0..number-1
			self.groups.create(name: "#{self.name} #{(n+65).chr}")
		end
		
		# randomize students
		students = self.users.student.shuffle
		
		# get the new groups
		groups = self.groups.to_a
		
		# divide students into groups and assign their group each
		students.in_groups(number).each do |student_group|
			User.where("id in (?)", student_group).update_all(group_id: groups.pop.id)
		end
	end

end

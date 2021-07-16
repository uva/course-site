class AddPropertiesToUser < ActiveRecord::Migration[6.0]
  def change
    add_column :users, :login, :string
    add_column :users, :student_number, :string
    add_column :users, :affiliation, :string
    add_column :users, :organization, :string
  end
end

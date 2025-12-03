# frozen_string_literal: true

VERSION = "2.0.0"

NEW_CONSTANT = "This is new in template"

def existing_method
  puts "exists in both"
end

def new_template_method
  puts "Only in template"
end

class NewTemplateClass
  def initialize
    @name = "new"
  end
end

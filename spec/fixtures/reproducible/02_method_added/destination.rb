# frozen_string_literal: true

class MyClass
  VERSION = "1.0.0"

  def initialize(name)
    @name = name
  end

  def name
    @name
  end

  def custom_method(options = {})
    options.fetch(:default, @name)
  end
end

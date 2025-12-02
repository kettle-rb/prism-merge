# coding: utf-8
# frozen_string_literal: true

# This is a "preamble" destination comment.

# This is a "frozen" destination comment.
# kettle-dev:freeze
# To retain chunks of destination comments & code during kettle-dev templating:
# Wrap custom sections with freeze markers (e.g., as above and below this comment chunk).
# The content between those markers will be preserved across template runs.
# kettle-dev:unfreeze

# This is a multi-line destination header comment attached to code.
# Hello Banana!
def example_method(arg1, arg2)
  puts "This is an example method with arguments: #{arg1}, #{arg2}"
end
# This is a multi-line destination footer comment attached to code.

example_method("goo", "jar")

# This is a single-line destination comment that should remain relatively placed.

example_method("hoo", "car")

# This is a destination single-line method attached above lines of code.
example_method("foo", "bar")
example_method("moo", "tar")
# This is a destination single-line comment attached below lines of code.

# This is a destination "postamble" comment.

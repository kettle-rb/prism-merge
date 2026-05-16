# frozen_string_literal: true

require_relative "spec_helper"
require "rake"

RSpec.describe "kettle-jem Rake tasks" do
  around do |example|
    previous = Rake.application
    Rake.application = Rake::Application.new
    Kettle::Jem.install_tasks
    example.run
  ensure
    Rake.application = previous
  end

  it "registers the public kettle:jem task surface" do
    expect(Rake::Task.task_defined?("kettle:jem:prepare")).to be(true)
    expect(Rake::Task.task_defined?("kettle:jem:template")).to be(true)
    expect(Rake::Task.task_defined?("kettle:jem:install")).to be(true)
    expect(Rake::Task.task_defined?("kettle:jem:selftest")).to be(true)
  end

  it "delegates prepare to the active task implementation" do
    expect(Kettle::Jem::Tasks::PrepareTask).to receive(:run)

    Rake::Task["kettle:jem:prepare"].invoke
  end

  it "delegates template to the active task implementation" do
    expect(Kettle::Jem::Tasks::TemplateTask).to receive(:run)

    Rake::Task["kettle:jem:template"].invoke
  end

  it "delegates install to the active task implementation without invoking template" do
    expect(Kettle::Jem::Tasks::InstallTask).to receive(:run)
    expect(Kettle::Jem::Tasks::TemplateTask).not_to receive(:run)

    Rake::Task["kettle:jem:install"].invoke
  end

  it "delegates selftest to the active task implementation" do
    expect(Kettle::Jem::Tasks::SelfTestTask).to receive(:run)

    Rake::Task["kettle:jem:selftest"].invoke
  end
end

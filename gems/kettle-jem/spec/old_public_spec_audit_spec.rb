# frozen_string_literal: true

require_relative "spec_helper"

RSpec.describe "old Kettle/Jem public spec audit" do
  it "records migration decisions for every old executable and task spec family" do
    audit = JSON.parse(
      File.read(File.join(__dir__, "fixtures", "old_public_spec_audit.json")),
      symbolize_names: true
    )

    expect(audit.fetch(:case_id)).to eq("kettle-jem-old-public-spec-audit")
    expect(audit.fetch(:policy)).to include("Port public behavior")

    files = audit.fetch(:files)
    expect(files.map { |entry| entry.fetch(:path) }).to contain_exactly(
      "spec/bin/setup_spec.rb",
      "spec/kettle/jem/setup_cli_spec.rb",
      "spec/kettle/jem/tasks/install_task_spec.rb",
      "spec/kettle/jem/tasks/prepare_task_spec.rb",
      "spec/kettle/jem/tasks/self_test_task_spec.rb",
      "spec/kettle/jem/tasks/template_task_include_spec.rb",
      "spec/kettle/jem/tasks/template_task_spec.rb",
      "spec/kettle/jem/version_gem_bootstrap_spec.rb",
      "spec/kettle/jem/rakelib/prepare_spec.rb",
      "spec/kettle/jem/rakelib/selftest_spec.rb",
      "spec/kettle/jem/rakelib/tasks_spec.rb",
      "spec/kettle/jem/self_test/manifest_spec.rb",
      "spec/kettle/jem/self_test/reporter_spec.rb"
    )
    expect(files).to all(include(:status, :active_specs))
    expect(files.map { |entry| entry.fetch(:status) }).to all(eq("ported"))
    expect(files.flat_map { |entry| entry.fetch(:remaining_behaviors, []) }).to be_empty

    template_task = files.find { |entry| entry.fetch(:path) == "spec/kettle/jem/tasks/template_task_spec.rb" }
    expect(template_task.fetch(:ported_behaviors)).to include(
      "legacy Markdown README H1, nested subsection, and fenced-code preservation"
    )
  end
end

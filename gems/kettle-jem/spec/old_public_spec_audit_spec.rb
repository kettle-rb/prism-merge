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
      "spec/kettle/jem/rakelib/prepare_spec.rb",
      "spec/kettle/jem/rakelib/selftest_spec.rb",
      "spec/kettle/jem/rakelib/tasks_spec.rb",
      "spec/kettle/jem/self_test/manifest_spec.rb",
      "spec/kettle/jem/self_test/reporter_spec.rb"
    )
    expect(files).to all(include(:status, :active_specs))
    expect(files.map { |entry| entry.fetch(:status) }).to include("partially_ported")

    pending = files.select { |entry| entry.fetch(:status) == "partially_ported" }
    expect(pending).to all(include(:ported_behaviors, :remaining_behaviors))
    expect(pending.flat_map { |entry| entry.fetch(:remaining_behaviors) }).to include(
      "unbundled versus bundled setup handoff",
      "include/only recipe filtering",
      "per-file recipe overrides parity"
    )
  end
end

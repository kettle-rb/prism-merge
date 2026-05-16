# frozen_string_literal: true

require_relative "spec_helper"

RUBY_MERGE = ::Ruby::Merge

RSpec.describe "Ruby::Merge" do
  def fixtures_root
    Pathname(__dir__).join("..", "..", "..", "..", "fixtures").expand_path
  end

  def read_json(path)
    Ast::Merge.normalize_value(JSON.parse(path.read))
  end

  def json_ready(value)
    Ast::Merge.json_ready(value)
  end

  it "conforms to the Ruby family substrate fixtures" do
    feature_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-214-ruby-family-feature-profile", "ruby-feature-profile.json")
    )
    backend_fixture = read_json(
      fixtures_root.join(
        "diagnostics",
        "slice-215-ruby-family-backend-feature-profiles",
        "ruby-ruby-backend-feature-profiles.json"
      )
    )
    plan_fixture = read_json(
      fixtures_root.join("diagnostics", "slice-216-ruby-family-plan-contexts", "ruby-ruby-plan-contexts.json")
    )
    manifest_fixture = read_json(
      fixtures_root.join("conformance", "slice-217-ruby-family-manifest", "ruby-family-manifest.json")
    )
    analysis_fixture = read_json(fixtures_root.join("ruby", "slice-218-analysis", "module-owners.json"))
    matching_fixture = read_json(fixtures_root.join("ruby", "slice-219-matching", "path-equality.json"))
    surfaces_fixture = read_json(
      fixtures_root.join("ruby", "slice-220-discovered-surfaces", "doc-comment-surfaces.json")
    )
    child_fixture = read_json(
      fixtures_root.join("ruby", "slice-221-delegated-child-operations", "yard-example-child-operations.json")
    )

    expect(json_ready(RUBY_MERGE.ruby_feature_profile)).to eq(json_ready(feature_fixture[:feature_profile]))
    expect(json_ready(RUBY_MERGE.available_ruby_backends.map(&:to_h))).to eq(
      json_ready([{ id: "kreuzberg-language-pack", family: "tree-sitter" }])
    )
    expect(json_ready(TreeHaver::BackendRegistry.fetch("kreuzberg-language-pack")&.to_h)).to eq(
      json_ready({ id: "kreuzberg-language-pack", family: "tree-sitter" })
    )
    expect(json_ready(RUBY_MERGE.ruby_backend_feature_profile)).to eq(
      json_ready(backend_fixture[:tree_sitter].merge(family: "ruby", supported_dialects: ["ruby"]))
    )
    expect(json_ready(RUBY_MERGE.ruby_plan_context)).to eq(json_ready(plan_fixture[:tree_sitter]))
    expect(Ast::Merge.conformance_fixture_path(manifest_fixture, "ruby", "analysis")).to eq(
      %w[ruby slice-218-analysis module-owners.json]
    )
    expect(Ast::Merge.conformance_fixture_path(manifest_fixture, "ruby", "merge")).to eq(
      %w[ruby slice-287-merge module-merge.json]
    )

    analysis = RUBY_MERGE.parse_ruby(analysis_fixture[:source], analysis_fixture[:dialect])
    expect(analysis[:ok]).to be(true)
    expect(json_ready(analysis.dig(:analysis, :owners))).to eq(json_ready(analysis_fixture.dig(:expected, :owners)))

    template = RUBY_MERGE.parse_ruby(matching_fixture[:template], matching_fixture[:dialect])
    destination = RUBY_MERGE.parse_ruby(matching_fixture[:destination], matching_fixture[:dialect])
    matching = RUBY_MERGE.match_ruby_owners(template[:analysis], destination[:analysis])
    expect(json_ready(matching[:matched].map { |match| [match[:template_path], match[:destination_path]] })).to eq(
      json_ready(matching_fixture.dig(:expected, :matched))
    )
    expect(json_ready(matching[:unmatched_template])).to eq(json_ready(matching_fixture.dig(:expected, :unmatched_template)))
    expect(json_ready(matching[:unmatched_destination])).to eq(
      json_ready(matching_fixture.dig(:expected, :unmatched_destination))
    )

    merge_fixture = read_json(fixtures_root.join("ruby", "slice-287-merge", "module-merge.json"))
    merge_result = RUBY_MERGE.merge_ruby(merge_fixture[:template], merge_fixture[:destination], "ruby")
    expect(merge_result[:ok]).to eq(merge_fixture.dig(:expected, :ok))
    expect(merge_result[:output]).to eq(merge_fixture.dig(:expected, :output))

    advanced_leaf_fixture = read_json(
      fixtures_root.join("ruby", "slice-720-advanced-leaf-merge", "class-hash-leaf-merge.json")
    )
    advanced_leaf_result = RUBY_MERGE.merge_ruby(
      advanced_leaf_fixture[:template],
      advanced_leaf_fixture[:destination],
      "ruby"
    )
    expect(advanced_leaf_result[:ok]).to eq(advanced_leaf_fixture.dig(:expected, :ok))
    expect(advanced_leaf_result[:output]).to eq(advanced_leaf_fixture.dig(:expected, :output))

    class_method_fixture = read_json(
      fixtures_root.join("ruby", "slice-941-template-only-class-method-merge", "class-method-merge.json")
    )
    class_method_result = RUBY_MERGE.merge_ruby(
      class_method_fixture[:template],
      class_method_fixture[:destination],
      "ruby"
    )
    expect(class_method_result[:ok]).to eq(class_method_fixture.dig(:expected, :ok))
    expect(class_method_result[:output]).to eq(class_method_fixture.dig(:expected, :output))

    method_visibility_fixture = read_json(
      fixtures_root.join(
        "ruby",
        "slice-942-template-only-method-visibility-ordering",
        "public-method-before-private-section.json"
      )
    )
    method_visibility_result = RUBY_MERGE.merge_ruby(
      method_visibility_fixture[:template],
      method_visibility_fixture[:destination],
      "ruby"
    )
    expect(method_visibility_result[:ok]).to eq(method_visibility_fixture.dig(:expected, :ok))
    expect(method_visibility_result[:output]).to eq(method_visibility_fixture.dig(:expected, :output))

    nested_class_fixture = read_json(
      fixtures_root.join("ruby", "slice-943-nested-class-method-merge", "nested-class-method-merge.json")
    )
    nested_class_result = RUBY_MERGE.merge_ruby(
      nested_class_fixture[:template],
      nested_class_fixture[:destination],
      "ruby"
    )
    expect(nested_class_result[:ok]).to eq(nested_class_fixture.dig(:expected, :ok))
    expect(nested_class_result[:output]).to eq(nested_class_fixture.dig(:expected, :output))

    template_nested_class_fixture = read_json(
      fixtures_root.join(
        "ruby",
        "slice-944-template-only-nested-declaration-merge",
        "template-only-nested-class-merge.json"
      )
    )
    template_nested_class_result = RUBY_MERGE.merge_ruby(
      template_nested_class_fixture[:template],
      template_nested_class_fixture[:destination],
      "ruby"
    )
    expect(template_nested_class_result[:ok]).to eq(template_nested_class_fixture.dig(:expected, :ok))
    expect(template_nested_class_result[:output]).to eq(template_nested_class_fixture.dig(:expected, :output))

    private_method_fixture = read_json(
      fixtures_root.join(
        "ruby",
        "slice-945-template-owned-private-method-merge",
        "private-method-section-merge.json"
      )
    )
    private_method_result = RUBY_MERGE.merge_ruby(
      private_method_fixture[:template],
      private_method_fixture[:destination],
      "ruby"
    )
    expect(private_method_result[:ok]).to eq(private_method_fixture.dig(:expected, :ok))
    expect(private_method_result[:output]).to eq(private_method_fixture.dig(:expected, :output))

    existing_private_fixture = read_json(
      fixtures_root.join(
        "ruby",
        "slice-946-existing-private-section-method-merge",
        "private-method-into-existing-section.json"
      )
    )
    existing_private_result = RUBY_MERGE.merge_ruby(
      existing_private_fixture[:template],
      existing_private_fixture[:destination],
      "ruby"
    )
    expect(existing_private_result[:ok]).to eq(existing_private_fixture.dig(:expected, :ok))
    expect(existing_private_result[:output]).to eq(existing_private_fixture.dig(:expected, :output))

    invalid_template_fixture = read_json(fixtures_root.join("ruby", "slice-287-merge", "invalid-template.json"))
    invalid_template_result = RUBY_MERGE.merge_ruby(
      invalid_template_fixture[:template],
      invalid_template_fixture[:destination],
      "ruby"
    )
    expect(invalid_template_result[:ok]).to be(false)
    expect(
      json_ready(
        invalid_template_result[:diagnostics].map { |entry| entry.slice(:severity, :category) }
      )
    ).to eq(json_ready(invalid_template_fixture.dig(:expected, :diagnostics)))

    invalid_destination_fixture = read_json(fixtures_root.join("ruby", "slice-287-merge", "invalid-destination.json"))
    invalid_destination_result = RUBY_MERGE.merge_ruby(
      invalid_destination_fixture[:template],
      invalid_destination_fixture[:destination],
      "ruby"
    )
    expect(invalid_destination_result[:ok]).to be(false)
    expect(
      json_ready(
        invalid_destination_result[:diagnostics].map { |entry| entry.slice(:severity, :category) }
      )
    ).to eq(json_ready(invalid_destination_fixture.dig(:expected, :diagnostics)))

    gemfile_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        source "https://gem.coop"
        gemspec
        eval_gemfile "gemfiles/modular/style.gemfile"
        gem "rake"
      RUBY
      <<~RUBY,
        source "https://rubygems.org"
        gem "rspec"
        eval_gemfile "gemfiles/modular/style.gemfile"
      RUBY
      "ruby"
    )
    expect(gemfile_merge[:ok]).to be(true)
    expect(gemfile_merge[:output]).to include('source "https://gem.coop"')
    expect(gemfile_merge[:output]).to include("gemspec")
    expect(gemfile_merge[:output].scan('eval_gemfile "gemfiles/modular/style.gemfile"').size).to eq(1)
    expect(gemfile_merge[:output]).to include('gem "rspec"')
    expect(gemfile_merge[:output]).to include('gem "rake"')

    modular_gemfile_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        gem "reek", "~> 6.5"

        platform :mri do
          gem "rubocop-lts", "~> 23.0"
          gem "rubocop-ruby2_3"
        end
      RUBY
      <<~RUBY,
        # frozen_string_literal: true

        # Destination style guidance.

        gem "reek", "~> 6.5"

        platform :mri do
          gem "rubocop-lts", "~> 24.0"
          gem "rubocop-ruby3_2"
        end
      RUBY
      "ruby"
    )
    expect(modular_gemfile_merge[:ok]).to be(true)
    expect(modular_gemfile_merge[:output]).to include("# frozen_string_literal: true")
    expect(modular_gemfile_merge[:output]).to include("# Destination style guidance.")
    expect(modular_gemfile_merge[:output]).to include("platform :mri do")
    expect(modular_gemfile_merge[:output]).to include('gem "rubocop-ruby3_2"')

    rakefile_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        desc "Default task"
        task :default do
          puts "template"
        end

        desc "CI"
        task :ci do
          sh "bundle exec rspec"
        end
      RUBY
      <<~RUBY,
        desc "Default task"
        task :default do
          puts "destination"
        end
      RUBY
      "ruby"
    )
    expect(rakefile_merge[:ok]).to be(true)
    expect(rakefile_merge[:output].scan(/task\s+:default/).size).to eq(1)
    expect(rakefile_merge[:output]).to include('puts "destination"')
    expect(rakefile_merge[:output]).to include("task :ci")

    relocated_rakefile_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        # Define a base default task early so other files can enhance it.
        desc "Default tasks aggregator"
        task :default do
          puts "Default task complete."
        end

        # External gems that define tasks - add here!
        require "kettle/dev"
      RUBY
      <<~RUBY,
        # Define a base default task early so other files can enhance it.
        desc "Default tasks aggregator"
        # External gems that define tasks - add here!
        require "kettle/dev"

        task :default do
          # :nocov:
          puts "Default task complete."
          # :nocov:
        end
      RUBY
      "ruby"
    )
    expect(relocated_rakefile_merge[:ok]).to be(true)
    expect(relocated_rakefile_merge[:output].scan(/task\s+:default/).size).to eq(1)
    expect(relocated_rakefile_merge[:output].scan("# :nocov:").size).to eq(2)
    expect(relocated_rakefile_merge[:output]).to include('desc "Default tasks aggregator"')
    expect(relocated_rakefile_merge[:output]).to include(<<~RUBY)
      task :default do
        # :nocov:
        puts "Default task complete."
        # :nocov:
      end
    RUBY
    expect(relocated_rakefile_merge[:output].index('desc "Default tasks aggregator"')).to be <
      relocated_rakefile_merge[:output].index("task :default do")

    rescue_task_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        begin
          require "kettle/jem"
        rescue LoadError
          desc("(stub) kettle:jem:selftest is unavailable")
          task("kettle:jem:selftest") do
            warn("NOTE: not installed")
          end
        end
      RUBY
      <<~RUBY,
        begin
          require "kettle/jem"
        rescue LoadError
          # :nocov:
          desc("(stub) kettle:jem:selftest is unavailable")
          task("kettle:jem:selftest") do
            warn("NOTE: not installed")
          end
          # :nocov:
        end
      RUBY
      "ruby"
    )
    expect(rescue_task_merge[:ok]).to be(true)
    expect(rescue_task_merge[:output].scan('task("kettle:jem:selftest")').size).to eq(1)
    expect(rescue_task_merge[:output].scan("# :nocov:").size).to eq(2)

    rakefile_require_merge = RUBY_MERGE.merge_ruby(
      <<~RUBY,
        require "kettle/dev"
      RUBY
      <<~RUBY,
        require "bundler/setup"
      RUBY
      "ruby",
      merge_template_requires: true
    )
    expect(rakefile_require_merge[:ok]).to be(true)
    expect(rakefile_require_merge[:output]).to include('require "bundler/setup"')
    expect(rakefile_require_merge[:output]).to include('require "kettle/dev"')

    surfaces_analysis = RUBY_MERGE.parse_ruby(surfaces_fixture[:source], "ruby")
    expect(surfaces_analysis[:ok]).to be(true)
    expect(json_ready(RUBY_MERGE.ruby_discovered_surfaces(surfaces_analysis[:analysis]))).to eq(
      json_ready(surfaces_fixture[:expected])
    )

    child_analysis = RUBY_MERGE.parse_ruby(child_fixture[:source], "ruby")
    expect(child_analysis[:ok]).to be(true)
    expect(
      json_ready(
        RUBY_MERGE.ruby_delegated_child_operations(
          child_analysis[:analysis],
          parent_operation_id: child_fixture[:parent_operation_id]
        )
      )
    ).to eq(json_ready(child_fixture[:expected]))

    grouped_fixture = read_json(
      fixtures_root.join("ruby", "slice-229-projected-child-review-groups", "yard-example-review-groups.json")
    )
    expect(json_ready(Ast::Merge.group_projected_child_review_cases(grouped_fixture[:cases]))).to eq(
      json_ready(grouped_fixture[:expected_groups])
    )

    progress_fixture = read_json(
      fixtures_root.join("ruby", "slice-232-projected-child-review-group-progress", "yard-example-review-progress.json")
    )
    expect(
      json_ready(
        Ast::Merge.summarize_projected_child_review_group_progress(
          progress_fixture[:groups],
          progress_fixture[:resolved_case_ids]
        )
      )
    ).to eq(json_ready(progress_fixture[:expected_progress]))

    ready_fixture = read_json(
      fixtures_root.join("ruby", "slice-235-projected-child-review-groups-ready-for-apply", "yard-example-ready-groups.json")
    )
    expect(
      json_ready(
        Ast::Merge.select_projected_child_review_groups_ready_for_apply(
          ready_fixture[:groups],
          ready_fixture[:resolved_case_ids]
        )
      )
    ).to eq(json_ready(ready_fixture[:expected_ready_groups]))

    transport_fixture = read_json(
      fixtures_root.join("ruby", "slice-239-delegated-child-review-transport", "yard-example-review-transport.json")
    )
    expect(
      json_ready(
        Ast::Merge.projected_child_group_review_request(transport_fixture[:group], transport_fixture[:family])
      )
    ).to eq(json_ready(transport_fixture[:expected_request]))
    expect(
      json_ready(
        Ast::Merge.select_projected_child_review_groups_accepted_for_apply(
          transport_fixture[:groups],
          transport_fixture[:family],
          transport_fixture[:decisions]
        )
      )
    ).to eq(json_ready(transport_fixture[:expected_accepted_groups]))

    state_fixture = read_json(
      fixtures_root.join("ruby", "slice-242-delegated-child-review-state", "yard-example-review-state.json")
    )
    expect(
      json_ready(
        Ast::Merge.review_projected_child_groups(
          state_fixture[:groups],
          state_fixture[:family],
          state_fixture[:decisions]
        )
      )
    ).to eq(json_ready(state_fixture[:expected_state]))

    apply_plan_fixture = read_json(
      fixtures_root.join("ruby", "slice-245-delegated-child-apply-plan", "yard-example-apply-plan.json")
    )
    expect(
      json_ready(
        Ast::Merge.delegated_child_apply_plan(
          apply_plan_fixture[:review_state],
          apply_plan_fixture[:family]
        )
      )
    ).to eq(json_ready(apply_plan_fixture[:expected_plan]))

    apply_output_fixture = read_json(
      fixtures_root.join("ruby", "slice-289-delegated-child-apply-output", "yard-example-applied-output.json")
    )
    apply_output_result = RUBY_MERGE.apply_ruby_delegated_child_outputs(
      apply_output_fixture[:source],
      apply_output_fixture[:delegated_operations],
      apply_output_fixture[:apply_plan],
      apply_output_fixture[:applied_children]
    )
    expect(apply_output_result[:ok]).to eq(apply_output_fixture.dig(:expected, :ok))
    expect(apply_output_result[:output]).to eq(apply_output_fixture.dig(:expected, :output))

    nested_merge_fixture = read_json(
      fixtures_root.join("ruby", "slice-291-nested-merge", "yard-example-nested-merge.json")
    )
    nested_merge_result = RUBY_MERGE.merge_ruby_with_nested_outputs(
      nested_merge_fixture[:template],
      nested_merge_fixture[:destination],
      "ruby",
      nested_merge_fixture[:nested_outputs]
    )
    expect(nested_merge_result[:ok]).to eq(nested_merge_fixture.dig(:expected, :ok))
    expect(nested_merge_result[:output]).to eq(nested_merge_fixture.dig(:expected, :output))

    reviewed_nested_merge_fixture = read_json(
      fixtures_root.join("ruby", "slice-299-reviewed-nested-merge", "yard-example-reviewed-nested-merge.json")
    )
    reviewed_nested_merge_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs(
      reviewed_nested_merge_fixture[:template],
      reviewed_nested_merge_fixture[:destination],
      "ruby",
      reviewed_nested_merge_fixture[:review_state],
      reviewed_nested_merge_fixture[:applied_children]
    )
    expect(reviewed_nested_merge_result[:ok]).to eq(reviewed_nested_merge_fixture.dig(:expected, :ok))
    expect(reviewed_nested_merge_result[:output]).to eq(reviewed_nested_merge_fixture.dig(:expected, :output))

    review_artifact_fixture = read_json(
      fixtures_root.join(
        "ruby",
        "slice-310-reviewed-nested-review-artifact-application",
        "yard-example-reviewed-nested-review-artifact-application.json"
      )
    )
    replay_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
      review_artifact_fixture[:template],
      review_artifact_fixture[:destination],
      "ruby",
      review_artifact_fixture[:replay_bundle]
    )
    expect(replay_result[:ok]).to eq(review_artifact_fixture.dig(:expected, :ok))
    expect(replay_result[:output]).to eq(review_artifact_fixture.dig(:expected, :output))
    state_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state(
      review_artifact_fixture[:template],
      review_artifact_fixture[:destination],
      "ruby",
      review_artifact_fixture[:review_state]
    )
    expect(state_result[:ok]).to eq(review_artifact_fixture.dig(:expected, :ok))
    expect(state_result[:output]).to eq(review_artifact_fixture.dig(:expected, :output))

    rejection_fixture = read_json(
      fixtures_root.join(
        "ruby",
        "slice-312-reviewed-nested-review-artifact-rejection",
        "yard-example-reviewed-nested-review-artifact-rejection.json"
      )
    )
    replay_rejection = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle(
      rejection_fixture[:template],
      rejection_fixture[:destination],
      "ruby",
      rejection_fixture[:replay_bundle]
    )
    expect(json_ready(replay_rejection)).to eq(json_ready(rejection_fixture[:expected].merge(policies: [])))
    state_rejection = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state(
      rejection_fixture[:template],
      rejection_fixture[:destination],
      "ruby",
      rejection_fixture[:review_state]
    )
    expect(json_ready(state_rejection)).to eq(json_ready(rejection_fixture[:expected_review_state].merge(policies: [])))

    envelope_fixture = read_json(
      fixtures_root.join(
        "ruby",
        "slice-314-reviewed-nested-review-artifact-envelope-application",
        "yard-example-reviewed-nested-review-artifact-envelope-application.json"
      )
    )
    replay_envelope_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(
      envelope_fixture[:template],
      envelope_fixture[:destination],
      "ruby",
      envelope_fixture[:replay_bundle_envelope]
    )
    expect(replay_envelope_result[:ok]).to eq(envelope_fixture.dig(:expected, :ok))
    expect(replay_envelope_result[:output]).to eq(envelope_fixture.dig(:expected, :output))
    state_envelope_result = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(
      envelope_fixture[:template],
      envelope_fixture[:destination],
      "ruby",
      envelope_fixture[:review_state_envelope]
    )
    expect(state_envelope_result[:ok]).to eq(envelope_fixture.dig(:expected, :ok))
    expect(state_envelope_result[:output]).to eq(envelope_fixture.dig(:expected, :output))

    envelope_rejection_fixture = read_json(
      fixtures_root.join(
        "ruby",
        "slice-316-reviewed-nested-review-artifact-envelope-rejection",
        "yard-example-reviewed-nested-review-artifact-envelope-rejection.json"
      )
    )
    replay_envelope_rejection = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_replay_bundle_envelope(
      envelope_rejection_fixture[:template],
      envelope_rejection_fixture[:destination],
      "ruby",
      envelope_rejection_fixture[:replay_bundle_envelope]
    )
    expect(json_ready(replay_envelope_rejection)).to eq(json_ready(envelope_rejection_fixture[:expected_replay_bundle].merge(policies: [])))
    state_envelope_rejection = RUBY_MERGE.merge_ruby_with_reviewed_nested_outputs_from_review_state_envelope(
      envelope_rejection_fixture[:template],
      envelope_rejection_fixture[:destination],
      "ruby",
      envelope_rejection_fixture[:review_state_envelope]
    )
    expect(json_ready(state_envelope_rejection)).to eq(json_ready(envelope_rejection_fixture[:expected_review_state].merge(policies: [])))
  end
end

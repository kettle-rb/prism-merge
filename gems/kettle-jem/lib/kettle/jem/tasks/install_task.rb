# frozen_string_literal: true

require "fileutils"
require "open3"

module Kettle
  module Jem
    module Tasks
      module InstallTask
        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: {}, command_runner: method(:run_system_command))
          report = Kettle::Jem.apply_project(project_root, env: env, run_options: run_options)
          install_steps = []
          install_steps << gemspec_dependency_sync_step(report)
          install_steps << ensure_bin_setup_executable(project_root)
          install_steps.concat(run_bundle_setup_commands(project_root, env: env, run_options: run_options, command_runner: command_runner))
          install_steps << bundled_handoff_step(env: env, run_options: run_options)
          install_steps << bootstrap_commit_step(project_root, run_options: run_options)
          install_steps = execute_orchestration_steps(install_steps, project_root: project_root, env: env, run_options: run_options, command_runner: command_runner)

          report.merge(
            mode: "install",
            installed: true,
            install_steps: install_steps,
            install_phase_reports: install_phase_reports(install_steps),
            diagnostics: report.fetch(:diagnostics) + [{
              severity: "advisory",
              message: "kettle:jem:install applied templates, completed local post-template checks, and executed available orchestration steps.",
            }]
          )
        end

        def gemspec_dependency_sync_step(report)
          gemspec_report = report.fetch(:recipe_reports, []).find do |recipe_report|
            recipe_report.fetch(:relative_path, "").end_with?(".gemspec")
          end
          return {
            name: "gemspec_dependency_sync",
            status: "unavailable",
            reason: "no_gemspec_recipe",
          } unless gemspec_report

          {
            name: "gemspec_dependency_sync",
            path: gemspec_report.fetch(:relative_path),
            status: gemspec_report.fetch(:changed, false) ? "applied" : "already_current",
            development_dependencies: development_dependency_names(gemspec_report.fetch(:final_content, "")),
          }
        end

        def development_dependency_names(content)
          content.to_s.lines.filter_map do |line|
            line[/^\s*\w+\.add_development_dependency\s*(?:\(|\s)\s*["']([^"']+)["']/, 1]
          end.uniq
        end

        def install_phase_reports(install_steps)
          phases = {
            "template_apply" => %w[gemspec_dependency_sync],
            "post_template" => %w[bin_setup_executable bin_setup bundle_binstubs],
            "orchestration" => %w[bundled_handoff bootstrap_commit],
          }
          phases.map do |phase, names|
            steps = install_steps.select { |step| names.include?(step.fetch(:name).to_s) }
            {
              phase: phase,
              steps: steps.map { |step| step.fetch(:name) },
              statuses: steps.to_h { |step| [step.fetch(:name), step.fetch(:status)] },
            }
          end
        end

        def ensure_bin_setup_executable(project_root)
          path = File.join(project_root, "bin", "setup")
          return {name: "bin_setup_executable", path: "bin/setup", status: "missing"} unless File.exist?(path)

          before = File.stat(path).mode
          FileUtils.chmod(before | 0o111, path)
          after = File.stat(path).mode
          {
            name: "bin_setup_executable",
            path: "bin/setup",
            status: (before == after ? "already_executable" : "updated"),
          }
        end

        def run_bundle_setup_commands(project_root, env:, run_options:, command_runner:)
          quiet = Kettle::Jem::DecisionPolicy.value_to_boolean(run_options[:quiet])
          [
            run_command_step(
              "bin_setup",
              bin_setup_command(project_root, quiet: quiet),
              project_root: project_root,
              env: env,
              quiet: quiet,
              command_runner: command_runner
            ),
            run_command_step(
              "bundle_binstubs",
              %w[bundle binstubs --all],
              project_root: project_root,
              env: env,
              quiet: quiet,
              command_runner: command_runner
            ),
          ]
        end

        def execute_orchestration_steps(install_steps, project_root:, env:, run_options:, command_runner:)
          quiet = Kettle::Jem::DecisionPolicy.value_to_boolean(run_options[:quiet])
          install_steps.map do |step|
            case step.fetch(:name)
            when "bundled_handoff"
              execute_ready_command_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            when "bootstrap_commit"
              execute_ready_commands_step(step, project_root: project_root, env: env, quiet: quiet, command_runner: command_runner)
            else
              step
            end
          end
        end

        def bundled_handoff_step(env:, run_options:)
          if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:bootstrap_mode])
            return {
              name: "bundled_handoff",
              status: "skipped",
              reason: "bootstrap_mode",
            }
          end

          bundle_gemfile = (env || {})["BUNDLE_GEMFILE"].to_s.strip
          unless bundle_gemfile.empty?
            return {
              name: "bundled_handoff",
              status: "already_bundled",
              bundle_gemfile: bundle_gemfile,
            }
          end

          {
            name: "bundled_handoff",
            command: ["bundle", "exec", "kettle-jem"] + handoff_argv(run_options),
            status: "ready",
            reason: "ready_for_orchestration",
          }
        end

        def bootstrap_commit_step(project_root, run_options:)
          if Kettle::Jem::DecisionPolicy.value_to_boolean((run_options || {})[:skip_commit])
            return {
              name: "bootstrap_commit",
              status: "skipped",
              reason: "skip_commit",
            }
          end

          unless File.directory?(File.join(project_root, ".git")) &&
              git_success?(project_root, "rev-parse", "--is-inside-work-tree")
            return {
              name: "bootstrap_commit",
              status: "unavailable",
              reason: "not_git_repository",
            }
          end

          dirty_entries = git_output(project_root, "status", "--porcelain").lines.map(&:chomp).reject(&:empty?)
          return {
            name: "bootstrap_commit",
            status: "clean_noop",
            dirty_entries: [],
          } if dirty_entries.empty?

          commands = []
          commands << %w[bundle lock] if File.exist?(File.join(project_root, "Gemfile.lock"))
          commands << %w[git add -A]
          commands << ["git", "commit", "-m", "🎨 Template bootstrap by kettle-jem v#{Kettle::Jem::Version::VERSION}"]
          {
            name: "bootstrap_commit",
            status: "ready",
            dirty_entries: dirty_entries,
            commands: commands,
            reason: "ready_for_orchestration",
          }
        end

        def git_success?(project_root, *args)
          _stdout, _stderr, status = Open3.capture3("git", "-C", project_root.to_s, *args)
          status.success?
        end

        def git_output(project_root, *args)
          stdout, _stderr, status = Open3.capture3("git", "-C", project_root.to_s, *args)
          status.success? ? stdout : ""
        end

        def handoff_argv(run_options)
          options = run_options || {}
          argv = []
          argv << "--accept-config" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:accept_config])
          argv << "--skip-commit" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:skip_commit])
          argv << "--quiet" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:quiet])
          argv << "--verbose" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:verbose])
          argv << "--force" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:force])
          argv << "--accept" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:accept])
          argv << "--interactive" if Kettle::Jem::DecisionPolicy.value_to_boolean(options[:interactive])
          argv.concat(value_arg("--failure-mode", options[:failure_mode]))
          argv.concat(value_arg("--allowed", options[:allowed]))
          argv.concat(value_arg("--hook-templates", options[:hook_templates]))
          argv.concat(list_arg("--only", options[:only]))
          argv.concat(list_arg("--include", options[:include]))
          argv
        end

        def value_arg(flag, value)
          value.to_s.strip.empty? ? [] : [flag, value.to_s]
        end

        def list_arg(flag, value)
          values = Array(value).flat_map { |entry| entry.to_s.split(",") }.map(&:strip).reject(&:empty?)
          values.empty? ? [] : [flag, values.join(",")]
        end

        def bin_setup_command(project_root, quiet:)
          command = [File.join("bin", "setup")]
          command << "--quiet" if quiet && File.exist?(File.join(project_root, "bin", "setup"))
          command
        end

        def run_command_step(name, command, project_root:, env:, quiet:, command_runner:)
          if command.first == File.join("bin", "setup") && !File.exist?(File.join(project_root, "bin", "setup"))
            return {
              name: name,
              command: command,
              status: "skipped",
              reason: "missing bin/setup",
            }
          end

          result = command_runner.call(command, chdir: project_root, env: env, quiet: quiet)
          success = result.fetch(:success)
          return {
            name: name,
            command: command,
            status: "succeeded",
            exitstatus: result[:exitstatus],
          } if success

          raise Kettle::Jem::Error, "#{name} failed: #{command.join(" ")}\n#{result[:stderr]}"
        end

        def execute_ready_command_step(step, project_root:, env:, quiet:, command_runner:)
          return step unless step.fetch(:status) == "ready"

          result = command_runner.call(step.fetch(:command), chdir: project_root, env: env, quiet: quiet)
          return step.merge(
            status: "succeeded",
            exitstatus: result[:exitstatus],
            reason: "executed"
          ) if result.fetch(:success)

          raise Kettle::Jem::Error, "#{step.fetch(:name)} failed: #{step.fetch(:command).join(" ")}\n#{result[:stderr]}"
        end

        def execute_ready_commands_step(step, project_root:, env:, quiet:, command_runner:)
          return step unless step.fetch(:status) == "ready"

          results = step.fetch(:commands).map do |command|
            result = command_runner.call(command, chdir: project_root, env: env, quiet: quiet)
            unless result.fetch(:success)
              raise Kettle::Jem::Error, "#{step.fetch(:name)} failed: #{command.join(" ")}\n#{result[:stderr]}"
            end
            {
              command: command,
              exitstatus: result[:exitstatus],
            }
          end
          step.merge(
            status: "succeeded",
            command_results: results,
            reason: "executed"
          )
        end

        def run_system_command(command, chdir:, env:, quiet:)
          stdout, stderr, status = Open3.capture3(env || {}, *command, chdir: chdir)
          $stdout.print(stdout) if !quiet && !stdout.empty?
          $stderr.print(stderr) if !quiet && !stderr.empty?
          {
            success: status.success?,
            exitstatus: status.exitstatus,
            stdout: stdout,
            stderr: stderr,
          }
        end
      end
    end
  end
end

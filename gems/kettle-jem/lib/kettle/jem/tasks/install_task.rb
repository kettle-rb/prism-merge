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
          install_steps << ensure_bin_setup_executable(project_root)
          install_steps.concat(run_bundle_setup_commands(project_root, env: env, run_options: run_options, command_runner: command_runner))
          install_steps << bundled_handoff_step(env: env, run_options: run_options)

          report.merge(
            mode: "install",
            installed: true,
            install_steps: install_steps,
            diagnostics: report.fetch(:diagnostics) + [{
              severity: "advisory",
              message: "kettle:jem:install applied templates, completed local post-template checks, and reported the bundled handoff contract.",
            }]
          )
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
            reason: "reported_for_orchestration",
          }
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

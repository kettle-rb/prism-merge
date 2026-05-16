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

          report.merge(
            mode: "install",
            installed: true,
            install_steps: install_steps,
            diagnostics: report.fetch(:diagnostics) + [{
              severity: "advisory",
              message: "kettle:jem:install applied templates and completed local post-template checks; bundle setup/binstub execution parity is pending.",
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

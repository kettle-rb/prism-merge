# frozen_string_literal: true

require "fileutils"

module Kettle
  module Jem
    module Tasks
      module InstallTask
        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: {})
          report = Kettle::Jem.apply_project(project_root, env: env, run_options: run_options)
          install_steps = []
          install_steps << ensure_bin_setup_executable(project_root)

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
      end
    end
  end
end

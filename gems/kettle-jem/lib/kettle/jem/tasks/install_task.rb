# frozen_string_literal: true

module Kettle
  module Jem
    module Tasks
      module InstallTask
        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: {})
          Kettle::Jem.plan_project(project_root, env: env, run_options: run_options).merge(
            mode: "install",
            installed: false,
            diagnostics: [{
              severity: "advisory",
              message: "kettle:jem:install is registered; full bundle bootstrap parity is pending.",
            }]
          )
        end
      end
    end
  end
end

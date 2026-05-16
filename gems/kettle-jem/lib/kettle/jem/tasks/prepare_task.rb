# frozen_string_literal: true

module Kettle
  module Jem
    module Tasks
      module PrepareTask
        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: {})
          Kettle::Jem.plan_project(project_root, env: env, run_options: run_options)
        end
      end
    end
  end
end

# frozen_string_literal: true

module Kettle
  module Jem
    module Tasks
      module TemplateTask
        module_function

        def run(project_root: Dir.pwd, env: ENV, run_options: env_run_options(env))
          Kettle::Jem.apply_project(project_root, env: env, run_options: run_options)
        end

        def env_run_options(env)
          {
            accept: truthy?(env["accept"]) || truthy?(env["force"]),
            force: truthy?(env["force"]),
            interactive: falsey?(env["force"]),
            failure_mode: env["FAILURE_MODE"] || env["failure_mode"],
          }.compact
        end

        def truthy?(value)
          Kettle::Jem::DecisionPolicy.truthy?(value)
        end

        def falsey?(value)
          Kettle::Jem::DecisionPolicy.falsey?(value)
        end
      end
    end
  end
end

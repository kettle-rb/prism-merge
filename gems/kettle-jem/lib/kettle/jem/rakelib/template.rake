# frozen_string_literal: true

namespace :kettle do
  namespace :jem do
    desc "Apply the kettle-jem template to the current project"
    task :template do
      Kettle::Jem::Tasks::TemplateTask.run
    end
  end
end

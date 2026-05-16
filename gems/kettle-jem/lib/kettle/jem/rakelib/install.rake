# frozen_string_literal: true

namespace :kettle do
  namespace :jem do
    desc "Prepare the current project to run kettle-jem inside its own bundle"
    task :install do
      Kettle::Jem::Tasks::InstallTask.run
    end
  end
end

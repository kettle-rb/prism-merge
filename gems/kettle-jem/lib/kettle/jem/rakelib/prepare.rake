# frozen_string_literal: true

namespace :kettle do
  namespace :jem do
    desc "Prepare .kettle-jem.yml for templating by validating project/template facts"
    task :prepare do
      Kettle::Jem::Tasks::PrepareTask.run
    end
  end
end

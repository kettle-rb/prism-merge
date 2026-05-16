# frozen_string_literal: true

namespace :kettle do
  namespace :jem do
    desc "Validate a destination project against the kettle-jem template"
    task :selftest do
      Kettle::Jem::Tasks::SelfTestTask.run
    end
  end
end

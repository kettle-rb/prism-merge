# frozen_string_literal: true

# Test if and unless with same condition but different bodies

if defined?(Rails)
  # Template implementation
  Rails.application.config.load_defaults 7.0
end

unless ENV["SKIP_FEATURE"]
  # Template feature
  enable_feature(:new_ui)
end

if Rails.env.production?
  # Template production config
  config.cache_store = :redis_cache_store
end

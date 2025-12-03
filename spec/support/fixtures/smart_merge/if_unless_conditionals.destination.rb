# frozen_string_literal: true

# Destination has same conditions but different implementations

if defined?(Rails)
  # Destination implementation (custom)
  Rails.application.config.load_defaults 6.1
  Rails.application.config.custom_setting = true
end

unless ENV["SKIP_FEATURE"]
  # Destination feature (customized)
  enable_feature(:old_ui)
  enable_feature(:custom_feature)
end

if Rails.env.production?
  # Destination production config (custom)
  config.cache_store = :memory_store
  config.custom_production_flag = true
end

# Destination-only conditional
if ENV["EXTRA_FEATURE"]
  enable_extra_features
end

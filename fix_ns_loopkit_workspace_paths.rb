#!/usr/bin/env ruby

require 'xcodeproj'

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

target_names = ['NightscoutServiceKit', 'NightscoutServiceKitUI']
targets = target_names.map { |n| project.targets.find { |t| t.name == n } }.compact
abort '❌ Targets not found' if targets.empty?

def normalize_paths(value)
  case value
  when nil then []
  when String then [value]
  when Array then value
  else value.to_a
  end
end

workspace_products_path = '$(BUILD_ROOT)/../Build/Products/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)'

updated = false

targets.each do |t|
  t.build_configurations.each do |cfg|
    bs = cfg.build_settings

    fw = normalize_paths(bs['FRAMEWORK_SEARCH_PATHS'])
    desired = [
      '$(inherited)',
      '$(CONFIGURATION_BUILD_DIR)',
      '$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)',
      workspace_products_path
    ]
    desired.each do |p|
      unless fw.include?(p)
        fw << p
        updated = true
      end
    end
    bs['FRAMEWORK_SEARCH_PATHS'] = fw

    lib = normalize_paths(bs['LIBRARY_SEARCH_PATHS'])
    unless lib.include?(workspace_products_path)
      lib << workspace_products_path
      bs['LIBRARY_SEARCH_PATHS'] = lib
      updated = true
    end
  end
end

project.save
puts updated ? '✅ Added workspace Build/Products to search paths' : 'ℹ️ Search paths already contained workspace products'



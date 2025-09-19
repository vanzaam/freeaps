#!/usr/bin/env ruby

require 'xcodeproj'

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

target = project.targets.find { |t| t.name == 'NightscoutServiceKitPlugin' }
abort '❌ NightscoutServiceKitPlugin target not found' unless target

paths_to_add = [
  '$(inherited)',
  '$(CONFIGURATION_BUILD_DIR)',
  '$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)/PackageFrameworks'
]

def normalize_paths(value)
  case value
  when nil
    []
  when String
    [value]
  when Array
    value
  else
    value.to_a
  end
end

updated = false

target.build_configurations.each do |config|
  settings = config.build_settings

  # FRAMEWORK_SEARCH_PATHS
  existing_fw = normalize_paths(settings['FRAMEWORK_SEARCH_PATHS'])
  new_fw = (existing_fw + paths_to_add).uniq
  if new_fw != existing_fw
    settings['FRAMEWORK_SEARCH_PATHS'] = new_fw
    updated = true
  end

  # LIBRARY_SEARCH_PATHS (defensive)
  existing_lib = normalize_paths(settings['LIBRARY_SEARCH_PATHS'])
  new_lib = (existing_lib + paths_to_add).uniq
  if new_lib != existing_lib
    settings['LIBRARY_SEARCH_PATHS'] = new_lib
    updated = true
  end
end

project.save
puts updated ? '✅ Updated search paths for NightscoutServiceKitPlugin' : 'ℹ️ Search paths already correct'



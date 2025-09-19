#!/usr/bin/env ruby

require 'xcodeproj'

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

target_names = ['NightscoutServiceKit', 'NightscoutServiceKitUI']
targets = target_names.map { |n| project.targets.find { |t| t.name == n } }.compact
abort '❌ NightscoutServiceKit/KitUI targets not found' if targets.empty?

paths_to_add = [
  '$(inherited)',
  '$(CONFIGURATION_BUILD_DIR)',
  '$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)',
  '$(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)/PackageFrameworks'
]

def normalize_paths(value)
  case value
  when nil then []
  when String then [value]
  when Array then value
  else value.to_a
  end
end

updated = false

targets.each do |target|
  target.build_configurations.each do |config|
    bs = config.build_settings
    fw = normalize_paths(bs['FRAMEWORK_SEARCH_PATHS'])
    nf = (fw + paths_to_add).uniq
    if nf != fw
      bs['FRAMEWORK_SEARCH_PATHS'] = nf
      updated = true
    end

    lb = normalize_paths(bs['LIBRARY_SEARCH_PATHS'])
    nl = (lb + paths_to_add).uniq
    if nl != lb
      bs['LIBRARY_SEARCH_PATHS'] = nl
      updated = true
    end
  end
end

project.save
puts updated ? '✅ Updated LoopKit search paths for NightscoutServiceKit/KitUI' : 'ℹ️ LoopKit search paths already correct'



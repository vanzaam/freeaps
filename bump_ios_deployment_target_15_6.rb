#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Bumping iOS deployment target to 15.6 for all FreeAPS targets..."

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

modified = 0

project.build_configurations.each do |config|
  if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] && config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] < '15.6'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.6'
    modified += 1
  end
end

project.targets.each do |t|
  t.build_configurations.each do |config|
    if config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] && config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] < '15.6'
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.6'
      modified += 1
    end
  end
end

project.save

puts "✅ Updated settings (#{modified} entries)."



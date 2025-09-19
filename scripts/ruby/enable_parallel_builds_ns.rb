#!/usr/bin/env ruby

require 'xcodeproj'

proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(proj_path)

# Set Disable Manual Target Order Build Warning to YES on all targets to suppress cycles caused by manual order
project.targets.each do |t|
  t.build_configurations.each do |cfg|
    cfg.build_settings['DISABLE_MANUAL_TARGET_ORDER_BUILD_WARNING'] = 'YES'
  end
end

project.save
puts '✅ Enabled DISABLE_MANUAL_TARGET_ORDER_BUILD_WARNING=YES on NightscoutService targets'


#!/usr/bin/env ruby

require 'xcodeproj'

proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(proj_path)

plugin = project.targets.find { |t| t.name == 'NightscoutServiceKitPlugin' }
kit    = project.targets.find { |t| t.name == 'NightscoutServiceKit' }
abort '❌ NightscoutServiceKitPlugin or NightscoutServiceKit target not found' unless plugin && kit

unless plugin.dependencies.any? { |d| d.target == kit }
  dep = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
  dep.target = kit
  dep.name = kit.name
  plugin.dependencies << dep
end

project.save
puts '✅ Ensured NightscoutServiceKitPlugin depends on NightscoutServiceKit'


#!/usr/bin/env ruby

require 'xcodeproj'

proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(proj_path)

plugin = project.targets.find { |t| t.name == 'NightscoutServiceKitPlugin' }
abort '❌ NightscoutServiceKitPlugin target not found' unless plugin

removed = []

# 1) Remove target dependency to NightscoutServiceKitUI
plugin.dependencies.dup.each do |dep|
  proxy = dep.target_proxy
  next unless proxy
  if proxy.respond_to?(:remote_info) && proxy.remote_info == 'NightscoutServiceKitUI'
    plugin.dependencies.delete(dep)
    removed << 'dep:NightscoutServiceKitUI'
  end
end

# 2) Remove NightscoutServiceKitUI.framework from Frameworks build phase
fw_phase = plugin.frameworks_build_phase
fw_phase.files.dup.each do |bf|
  fr = bf.file_ref
  next unless fr
  if fr.path == 'NightscoutServiceKitUI.framework' || fr.display_name == 'NightscoutServiceKitUI.framework'
    fw_phase.files.delete(bf)
    removed << 'link:NightscoutServiceKitUI.framework'
  end
end

# 3) Remove NightscoutServiceKitUI.framework from Embed Frameworks phase
embed = plugin.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
if embed
  embed.files.dup.each do |bf|
    fr = bf.file_ref
    next unless fr
    if fr.path == 'NightscoutServiceKitUI.framework' || fr.display_name == 'NightscoutServiceKitUI.framework'
      embed.files.delete(bf)
      removed << 'embed:NightscoutServiceKitUI.framework'
    end
  end
end

project.save
puts "✅ Detached plugin from KitUI: #{removed.empty? ? 'nothing changed' : removed.join(', ')}"


#!/usr/bin/env ruby

require 'xcodeproj'

app_proj_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(app_proj_path)

removed = []

# Remove file references and build files for NightscoutServiceKitPlugin.loopplugin from all targets/phases
plugin_ref = project.files.find { |f| f.path == 'NightscoutServiceKitPlugin.loopplugin' }

project.targets.each do |t|
  t.copy_files_build_phases.each do |phase|
    next unless phase.name == 'Embed PlugIns'
    phase.files.dup.each do |bf|
      if bf.file_ref && bf.file_ref.path == 'NightscoutServiceKitPlugin.loopplugin'
        phase.files.delete(bf)
        removed << "removed from #{t.name}"
      end
    end
  end
end

# Also remove from top-level Frameworks group if present
if plugin_ref
  plugin_ref.remove_from_project
  removed << 'fileRef removed'
end

project.save
puts "✅ NightscoutServiceKitPlugin removed from Embed PlugIns (#{removed.uniq.join(', ')})"


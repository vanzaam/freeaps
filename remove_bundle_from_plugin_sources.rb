#!/usr/bin/env ruby

require 'xcodeproj'

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

plugin = project.targets.find { |t| t.name == 'NightscoutServiceKitPlugin' } or abort '❌ NightscoutServiceKitPlugin target not found'

removed = 0
plugin.build_phases.select { |p| p.isa == 'PBXSourcesBuildPhase' }.each do |phase|
  phase.files.dup.each do |bf|
    ref = bf.file_ref
    name = ref&.display_name || ref&.path
    if name == 'Bundle.swift' || (ref && ref.path&.end_with?('/Bundle.swift'))
      phase.remove_build_file(bf)
      removed += 1
    end
  end
end

project.save
puts "✅ Removed #{removed} Bundle.swift occurrences from NightscoutServiceKitPlugin sources"



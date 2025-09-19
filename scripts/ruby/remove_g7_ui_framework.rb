#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ Target FreeAPS not found' unless target

framework_name = 'G7SensorKitUI.framework'

removed = false

# Remove from Frameworks phase
if target.frameworks_build_phase
  target.frameworks_build_phase.files.each do |bf|
    ref = bf.file_ref
    ref_name = ref && (ref.path || ref.name)
    if ref_name && File.basename(ref_name) == framework_name
      target.frameworks_build_phase.remove_build_file(bf)
      removed = true
    end
  end
end

# Remove from any Copy Files (Embed Frameworks) phases
target.copy_files_build_phases.each do |phase|
  phase.files.each do |bf|
    ref = bf.file_ref
    ref_name = ref && (ref.path || ref.name)
    if ref_name && File.basename(ref_name) == framework_name
      phase.remove_build_file(bf)
      removed = true
    end
  end
end

# Remove dangling file references in project
project.files.each do |f|
  next unless f
  ref_name = f.path || f.name
  if ref_name && File.basename(ref_name) == framework_name
    f.remove_from_project
    removed = true
  end
end

project.save
puts (removed ? '✅ Removed G7SensorKitUI.framework from FreeAPS target' : 'ℹ️ No G7SensorKitUI.framework references found')

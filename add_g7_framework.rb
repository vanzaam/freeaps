#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
workspace_ref = 'Dependencies/G7SensorKit/G7SensorKit.xcodeproj'

project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ Target FreeAPS not found' unless target

# Find G7SensorKit products reference from the referenced project if already built
# We'll create a file reference to the built framework in BUILT_PRODUCTS_DIR which Xcode resolves at build time
frameworks_group = project.groups.find { |g| g.name == 'Frameworks' } || project.new_group('Frameworks')

framework_ref = project.new_file('G7SensorKit.framework', :built_products)
ui_framework_ref = project.new_file('G7SensorKitUI.framework', :built_products)

# Add to Frameworks phase
[target.frameworks_build_phase].each do |phase|
  phase.add_file_reference(framework_ref, true)
  phase.add_file_reference(ui_framework_ref, true)
end

# Ensure Embed Frameworks phase exists
embed_phase = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
embed_phase ||= project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed_phase.name = 'Embed Frameworks'
embed_phase.symbol_dst_subfolder_spec = :frameworks

target.build_phases << embed_phase unless target.build_phases.include?(embed_phase)

[framework_ref, ui_framework_ref].each do |ref|
  build_file = embed_phase.add_file_reference(ref, true)
  build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end

project.save

puts '✅ Linked G7SensorKit.framework and G7SensorKitUI.framework to FreeAPS target'

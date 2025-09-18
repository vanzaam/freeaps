#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Adding MedtrumKit to workspace and linking frameworks..."

workspace_file = 'FreeAPS.xcworkspace/contents.xcworkspacedata'
workspace_xml = File.read(workspace_file)

ref = "   <FileRef\n      location = \"group:Dependencies/MedtrumKit/MedtrumKit.xcodeproj\">\n   </FileRef>\n"

unless workspace_xml.include?('Dependencies/MedtrumKit/MedtrumKit.xcodeproj')
  updated = workspace_xml.sub("</Workspace>\n", "#{ref}</Workspace>\n")
  File.write(workspace_file, updated)
  puts "✅ Added MedtrumKit.xcodeproj to workspace"
else
  puts "ℹ️ MedtrumKit.xcodeproj already in workspace"
end

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ Target FreeAPS not found' unless target

# Create built products refs for MedtrumKit framework
frameworks_group = project.groups.find { |g| g.name == 'Frameworks' } || project.new_group('Frameworks')

medtrum_framework_ref = project.new_file('MedtrumKit.framework', :built_products)

# Link in Frameworks phase
target.frameworks_build_phase.add_file_reference(medtrum_framework_ref, true)

# Ensure Embed Frameworks phase exists
embed_phase = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
embed_phase ||= project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed_phase.name = 'Embed Frameworks'
embed_phase.symbol_dst_subfolder_spec = :frameworks
target.build_phases << embed_phase unless target.build_phases.include?(embed_phase)

bf = embed_phase.add_file_reference(medtrum_framework_ref, true)
bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }

project.save

puts '✅ Linked and embedded MedtrumKit.framework into FreeAPS target'
puts '📦 Next: resolve packages and clean derived data if needed.'



#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Linking OmniBLE into FreeAPS workspace and target..."

workspace_file = 'FreeAPS.xcworkspace/contents.xcworkspacedata'
workspace_xml = File.read(workspace_file)

omnible_proj_rel = 'Dependencies/OmniBLE/Dependencies/OmniBLE/OmniBLE.xcodeproj'
ref = "   <FileRef\n      location = \"group:#{omnible_proj_rel}\">\n   </FileRef>\n"

unless workspace_xml.include?(omnible_proj_rel)
  updated = workspace_xml.sub("</Workspace>\n", "#{ref}</Workspace>\n")
  File.write(workspace_file, updated)
  puts "✅ Added OmniBLE.xcodeproj to workspace"
else
  puts "ℹ️ OmniBLE.xcodeproj already in workspace"
end

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ Target FreeAPS not found' unless target

# Create built products refs
frameworks_group = project.groups.find { |g| g.name == 'Frameworks' } || project.new_group('Frameworks')

omnible_ref = project.new_file('OmniBLE.framework', :built_products)
omnible_ui_ref = project.new_file('OmniBLEUI.framework', :built_products)

# Link frameworks
target.frameworks_build_phase.add_file_reference(omnible_ref, true)
target.frameworks_build_phase.add_file_reference(omnible_ui_ref, true)

# Ensure Embed Frameworks
embed_phase = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
embed_phase ||= project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed_phase.name = 'Embed Frameworks'
embed_phase.symbol_dst_subfolder_spec = :frameworks
target.build_phases << embed_phase unless target.build_phases.include?(embed_phase)

[omnible_ref, omnible_ui_ref].each do |ref|
  bf = embed_phase.add_file_reference(ref, true)
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end

# Ensure Embed PlugIns
embed_plugins = target.copy_files_build_phases.find { |p| p.name == 'Embed PlugIns' }
unless embed_plugins
  embed_plugins = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_plugins.name = 'Embed PlugIns'
  embed_plugins.dst_subfolder_spec = '13'
  target.build_phases << embed_plugins
end

plugin_ref = project.new_file('OmniBLEPlugin.loopplugin', :built_products)
already = embed_plugins.files.any? { |f| f.display_name == 'OmniBLEPlugin.loopplugin' }
unless already
  bf = embed_plugins.add_file_reference(plugin_ref, true)
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  puts '✅ Embedded OmniBLEPlugin.loopplugin'
else
  puts 'ℹ️ OmniBLEPlugin.loopplugin already embedded'
end

project.save

puts '🎉 OmniBLE linking done.'



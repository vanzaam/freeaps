#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Embedding MedtrumKitPlugin.loopplugin into FreeAPS target..."

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ Target FreeAPS not found' unless target

# Ensure Embed PlugIns phase exists (dstSubfolderSpec = :plugins => 13)
embed_plugins_phase = target.copy_files_build_phases.find { |p| p.name == 'Embed PlugIns' }
unless embed_plugins_phase
  embed_plugins_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_plugins_phase.name = 'Embed PlugIns'
  # 13 == PlugIns (xcodeproj expects String here)
  embed_plugins_phase.dst_subfolder_spec = '13'
  target.build_phases << embed_plugins_phase
  puts "✅ Created 'Embed PlugIns' phase"
end

# Create built products file reference for plugin
plugin_ref = project.new_file('MedtrumKitPlugin.loopplugin', :built_products)

# Avoid duplicates in phase
already = embed_plugins_phase.files.any? { |f| f.display_name == 'MedtrumKitPlugin.loopplugin' }
unless already
  bf = embed_plugins_phase.add_file_reference(plugin_ref, true)
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  puts "✅ Added MedtrumKitPlugin.loopplugin to Embed PlugIns"
else
  puts "ℹ️ MedtrumKitPlugin.loopplugin already embedded"
end

project.save

puts '🎉 Done. Build the workspace scheme so Xcode builds the plugin target before embedding.'



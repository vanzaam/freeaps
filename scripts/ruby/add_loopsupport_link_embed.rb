#!/usr/bin/env ruby

require 'xcodeproj'

PROJECT_PATH = 'FreeAPS.xcodeproj'
TARGET_NAME = 'FreeAPS'
FRAMEWORKS = ['LoopSupportKitUI.framework']
PLUGIN = 'LoopSupportPlugin.loopplugin'

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME } or abort "❌ Target #{TARGET_NAME} not found"

fw_phase = target.frameworks_build_phase
embed = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
unless embed
  embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed Frameworks'
  embed.symbol_dst_subfolder_spec = :frameworks
  target.build_phases << embed
end

plugins = target.copy_files_build_phases.find { |p| p.name == 'Embed PlugIns' }
unless plugins
  plugins = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  plugins.name = 'Embed PlugIns'
  plugins.symbol_dst_subfolder_spec = :plug_ins
  target.build_phases << plugins
end

def find_file_ref(project, name)
  # Prefer file refs from LoopSupport products group if present
  ref = project.files.find { |f| (f.display_name == name) || (f.path == name) }
  unless ref
    ref = project.objects.select { |o| o.isa == 'PBXFileReference' }.find { |f| f.path == name || f.name == name }
  end
  ref
end

def has_item?(phase, name)
  phase.files.any? do |bf|
    n = bf.display_name || bf.file_ref&.display_name
    n == name
  end
end

added_link = []
added_embed = []
FRAMEWORKS.each do |fw_name|
  file_ref = find_file_ref(project, fw_name)
  next unless file_ref
  unless has_item?(fw_phase, fw_name)
    bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    bf.file_ref = file_ref
    fw_phase.files << bf
    added_link << fw_name
  end
  unless has_item?(embed, fw_name)
    bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    bf.file_ref = file_ref
    bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
    embed.files << bf
    added_embed << fw_name
  end
end

plugin_ref = find_file_ref(project, PLUGIN)
if plugin_ref && !has_item?(plugins, PLUGIN)
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.file_ref = plugin_ref
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  plugins.files << bf
end

project.save

puts "✅ Linking added: #{added_link.join(', ')}" unless added_link.empty?
puts "✅ Embedding added: #{added_embed.join(', ')}" unless added_embed.empty?
puts "ℹ️ Nothing to change" if added_link.empty? && added_embed.empty?

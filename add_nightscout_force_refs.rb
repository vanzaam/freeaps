#!/usr/bin/env ruby

require 'xcodeproj'

PROJECT_PATH = 'FreeAPS.xcodeproj'
TARGET_NAME = 'FreeAPS'
FRAMEWORKS = ['NightscoutServiceKit.framework', 'NightscoutServiceKitUI.framework']
PLUGIN = 'NightscoutServiceKitPlugin.loopplugin'

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == TARGET_NAME } or abort "❌ Target #{TARGET_NAME} not found"

frameworks_group = project.groups.find { |g| g.name == 'Frameworks' } || project.new_group('Frameworks')

# Ensure refs exist in BUILT_PRODUCTS_DIR
refs = {}
FRAMEWORKS.each do |fw|
  ref = project.files.find { |f| f.display_name == fw }
  unless ref
    ref = frameworks_group.new_file(fw)
    ref.last_known_file_type = 'wrapper.framework'
    ref.source_tree = 'BUILT_PRODUCTS_DIR'
  end
  refs[fw] = ref
end

plugin_ref = project.files.find { |f| f.display_name == PLUGIN }
unless plugin_ref
  plugin_ref = frameworks_group.new_file(PLUGIN)
  plugin_ref.last_known_file_type = 'wrapper.cfbundle'
  plugin_ref.source_tree = 'BUILT_PRODUCTS_DIR'
end

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

added_link = []
added_embed = []
refs.each do |name, ref|
  unless fw_phase.files.any? { |bf| (bf.display_name || bf.file_ref&.display_name) == name }
    bf = fw_phase.add_file_reference(ref, true)
    added_link << name
  end
  unless embed.files.any? { |bf| (bf.display_name || bf.file_ref&.display_name) == name }
    bf = embed.add_file_reference(ref, true)
    bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
    added_embed << name
  end
end

unless plugins.files.any? { |bf| (bf.display_name || bf.file_ref&.display_name) == PLUGIN }
  bf = plugins.add_file_reference(plugin_ref, true)
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
end

project.save

puts "✅ Linking added: #{added_link.join(', ')}" unless added_link.empty?
puts "✅ Embedding added: #{added_embed.join(', ')}" unless added_embed.empty?
puts "ℹ️ Nothing to change" if added_link.empty? && added_embed.empty?

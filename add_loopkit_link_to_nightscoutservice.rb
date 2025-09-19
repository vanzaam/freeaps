#!/usr/bin/env ruby

require 'xcodeproj'

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

target = project.targets.find { |t| t.name == 'NightscoutServiceKit' } or abort '❌ NightscoutServiceKit target not found'

frameworks_group = project.groups.find { |g| g.name == 'Frameworks' } || project.new_group('Frameworks')

def ensure_built_product_ref(project, group, name)
  ref = project.files.find { |f| f.display_name == name }
  unless ref
    ref = group.new_file(name)
    ref.last_known_file_type = 'wrapper.framework'
    ref.source_tree = 'BUILT_PRODUCTS_DIR'
  end
  ref
end

loopkit_ref = ensure_built_product_ref(project, frameworks_group, 'LoopKit.framework')
loopkitui_ref = ensure_built_product_ref(project, frameworks_group, 'LoopKitUI.framework')

fw = target.frameworks_build_phase

added = []
unless fw.files.any? { |bf| (bf.file_ref&.display_name) == 'LoopKit.framework' }
  fw.add_file_reference(loopkit_ref, true)
  added << 'LoopKit.framework'
end
unless fw.files.any? { |bf| (bf.file_ref&.display_name) == 'LoopKitUI.framework' }
  fw.add_file_reference(loopkitui_ref, true)
  added << 'LoopKitUI.framework'
end

project.save

puts added.empty? ? 'ℹ️ LoopKit frameworks already linked' : "✅ Linked: #{added.join(', ')}"



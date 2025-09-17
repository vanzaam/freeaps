#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'

project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ Target FreeAPS not found' unless target

frameworks_group = project.groups.find { |g| g.name == 'Frameworks' } || project.new_group('Frameworks')

onboarding_kit_ref = project.new_file('LoopOnboardingKit.framework', :built_products)
onboarding_ui_ref  = project.new_file('LoopOnboardingKitUI.framework', :built_products)

# Link frameworks
[target.frameworks_build_phase].each do |phase|
  phase.add_file_reference(onboarding_kit_ref, true)
  phase.add_file_reference(onboarding_ui_ref, true)
end

# Ensure Embed Frameworks phase exists
embed_phase = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
embed_phase ||= project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed_phase.name = 'Embed Frameworks'
embed_phase.symbol_dst_subfolder_spec = :frameworks
target.build_phases << embed_phase unless target.build_phases.include?(embed_phase)

[onboarding_kit_ref, onboarding_ui_ref].each do |ref|
  build_file = embed_phase.add_file_reference(ref, true)
  build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end

project.save

puts '✅ Linked LoopOnboardingKit.framework and LoopOnboardingKitUI.framework to FreeAPS target'



#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Removing LoopOnboardingKit links from FreeAPS target..."

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'FreeAPS' }
abort '❌ FreeAPS target not found' unless target

def remove_from_phase(phase, names)
  return unless phase
  phase.files.delete_if do |bf|
    n = bf.display_name || bf.file_ref&.display_name
    names.any? { |x| n&.include?(x) }
  end
end

names = ['LoopOnboardingKit.framework', 'LoopOnboardingKitUI.framework']

remove_from_phase(target.frameworks_build_phase, names)
embed = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
remove_from_phase(embed, names)

project.save
puts '✅ Removed LoopOnboardingKit and LoopOnboardingKitUI from Link/Embed'



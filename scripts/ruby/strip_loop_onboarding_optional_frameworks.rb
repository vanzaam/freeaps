#!/usr/bin/env ruby

require 'xcodeproj'

proj_path = 'Dependencies/LoopOnboarding/LoopOnboarding.xcodeproj'
project = Xcodeproj::Project.open(proj_path)

target_names = ['LoopOnboardingKitUI', 'LoopOnboardingPlugin']
framework_names = ['LoopSupportKitUI.framework', 'NightscoutServiceKit.framework']

targets = project.targets.select { |t| target_names.include?(t.name) }

removed = []

targets.each do |t|
  # Remove from Frameworks phase
  t.frameworks_build_phase.files.each do |bf|
    fr = bf.file_ref
    next unless fr && framework_names.include?(fr.path)
    removed << fr.path
    bf.remove_from_project
  end

  # Remove from any Copy Files (Embed Frameworks) phases
  t.copy_files_build_phases.each do |phase|
    phase.files.each do |bf|
      fr = bf.file_ref
      next unless fr && framework_names.include?(fr.path)
      removed << fr.path
      bf.remove_from_project
    end
  end
end

# Remove dangling file references from project groups
project.files.each do |fr|
  if framework_names.include?(fr.path)
    fr.remove_from_project
  end
end

project.save

if removed.empty?
  puts 'ℹ️ No optional frameworks found to remove.'
else
  puts "✅ Removed optional frameworks: #{removed.uniq.join(', ')}"
end



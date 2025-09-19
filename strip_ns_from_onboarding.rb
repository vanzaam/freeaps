#!/usr/bin/env ruby

require 'xcodeproj'

proj_path = 'Dependencies/LoopOnboarding/LoopOnboarding.xcodeproj'
project = Xcodeproj::Project.open(proj_path)

target = project.targets.find { |t| t.name == 'LoopOnboardingKitUI' }
abort '❌ LoopOnboardingKitUI target not found' unless target

removed = []

# Remove NightscoutServiceKit from Frameworks build phase
fw = target.frameworks_build_phase
fw.files.dup.each do |bf|
  if bf.display_name&.include?('NightscoutServiceKit')
    fw.files.delete(bf)
    removed << 'Frameworks'
  end
end

# Remove package product dependency if exists
target.package_product_dependencies.dup.each do |dep|
  if dep.product_name == 'NightscoutServiceKit'
    target.package_product_dependencies.delete(dep)
    removed << 'PackageProduct'
  end
end

project.save
puts "✅ Removed NightscoutServiceKit linkage from LoopOnboardingKitUI (#{removed.uniq.join(', ')})"


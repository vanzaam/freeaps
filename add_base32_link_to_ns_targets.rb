#!/usr/bin/env ruby

require 'xcodeproj'

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

target_names = ['NightscoutServiceKit', 'NightscoutServiceKitUI', 'NightscoutServiceKitPlugin']
targets = target_names.map { |n| project.targets.find { |t| t.name == n } }.compact
abort '❌ NightscoutService targets not found' if targets.empty?

# Find product dependency nodes
def product_dep(project, name)
  project.objects.select { |o| o.isa == 'XCSwiftPackageProductDependency' }.find { |p| p.product_name == name }
end

base32_prod = product_dep(project, 'Base32')
otp_prod = product_dep(project, 'OneTimePassword')

added = []
targets.each do |t|
  fw = t.frameworks_build_phase
  # Ensure Base32 present in Frameworks phase
  unless fw.files.any? { |bf| (bf.respond_to?(:product_ref) && bf.product_ref == base32_prod) || (bf.display_name == 'Base32') }
    if base32_prod
      bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
      bf.product_ref = base32_prod
      fw.files << bf
      added << "Base32->#{t.name}"
    end
  end
  # Ensure OTP present as well
  unless fw.files.any? { |bf| (bf.respond_to?(:product_ref) && bf.product_ref == otp_prod) || (bf.display_name == 'OneTimePassword') }
    if otp_prod
      bf2 = project.new(Xcodeproj::Project::Object::PBXBuildFile)
      bf2.product_ref = otp_prod
      fw.files << bf2
      added << "OTP->#{t.name}"
    end
  end
end

project.save
puts added.empty? ? 'ℹ️ Nothing to change' : "✅ Added links: #{added.join(', ')}"



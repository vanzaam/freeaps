#!/usr/bin/env ruby

require 'xcodeproj'

proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(proj_path)

plugin = project.targets.find { |t| t.name == 'NightscoutServiceKitPlugin' }
abort '❌ NightscoutServiceKitPlugin target not found' unless plugin

def find_product(project, name)
  project.objects.select { |o| o.isa == 'XCSwiftPackageProductDependency' && o.product_name == name }.first
end

base32_prod = find_product(project, 'Base32')
otp_prod    = find_product(project, 'OneTimePassword')
abort '❌ Base32 product not found in project' unless base32_prod
abort '❌ OneTimePassword product not found in project' unless otp_prod

added = []

# Ensure package product dependencies are attached to plugin
unless plugin.package_product_dependencies.include?(base32_prod)
  plugin.package_product_dependencies << base32_prod
  added << 'pkg:Base32'
end
unless plugin.package_product_dependencies.include?(otp_prod)
  plugin.package_product_dependencies << otp_prod
  added << 'pkg:OneTimePassword'
end

# Ensure Frameworks build phase has entries
fw_phase = plugin.frameworks_build_phase
def has_product_build_file?(phase, product)
  phase.files.any? do |bf|
    # PBXBuildFile stores productRef for package products
    bf_hash = bf.to_hash
    bf_hash['productRef'] == product.uuid
  end
end

unless has_product_build_file?(fw_phase, base32_prod)
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = base32_prod
  fw_phase.files << bf
  added << 'link:Base32'
end

unless has_product_build_file?(fw_phase, otp_prod)
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = otp_prod
  fw_phase.files << bf
  added << 'link:OneTimePassword'
end

project.save
puts "✅ Ensured NightscoutServiceKitPlugin deps: #{added.empty? ? 'already OK' : added.join(', ')}"


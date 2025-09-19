#!/usr/bin/env ruby

require 'xcodeproj'

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

target_names = ['NightscoutServiceKit', 'NightscoutServiceKitUI', 'NightscoutServiceKitPlugin']

targets = target_names.map { |n| project.targets.find { |t| t.name == n } }.compact
abort '❌ NightscoutService targets not found' if targets.empty?

# Ensure Base32 package reference exists
pkg_base32 = project.root_object.package_references.find do |p|
  p.respond_to?(:repositoryURL) && p.repositoryURL&.include?('mattrubin/Base32')
end

unless pkg_base32
  pkg_base32 = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg_base32.repositoryURL = 'https://github.com/mattrubin/Base32.git'
  pkg_base32.requirement = {
    'kind' => 'upToNextMajorVersion',
    'minimumVersion' => '1.1.0'
  }
  project.root_object.package_references << pkg_base32
end

# Ensure OTP package reference exists (for safety)
pkg_otp = project.root_object.package_references.find do |p|
  p.respond_to?(:repositoryURL) && p.repositoryURL&.include?('mattrubin/OneTimePassword')
end

unless pkg_otp
  pkg_otp = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg_otp.repositoryURL = 'https://github.com/mattrubin/OneTimePassword'
  pkg_otp.requirement = { 'kind' => 'branch', 'branch' => 'master' }
  project.root_object.package_references << pkg_otp
end

# Ensure product dependency on each target
added = []
targets.each do |target|
  unless target.package_product_dependencies.any? { |d| d.product_name == 'Base32' }
    prod = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    prod.product_name = 'Base32'
    prod.package = pkg_base32
    target.package_product_dependencies << prod
    added << "Base32->#{target.name}"
  end
  unless target.package_product_dependencies.any? { |d| d.product_name == 'OneTimePassword' }
    prod2 = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    prod2.product_name = 'OneTimePassword'
    prod2.package = pkg_otp
    target.package_product_dependencies << prod2
    added << "OTP->#{target.name}"
  end
end

project.save
puts "✅ Ensured packages: #{added.join(', ')}" unless added.empty?
puts "ℹ️ Packages already configured for all targets" if added.empty?



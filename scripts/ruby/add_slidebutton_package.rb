#!/usr/bin/env ruby

require 'xcodeproj'

PROJECT_PATH = 'FreeAPS.xcodeproj'
SLIDEBUTTON_URL = 'https://github.com/no-comment/SlideButton'
SLIDEBUTTON_PRODUCT = 'SlideButton'

puts "🔧 Ensuring SlideButton package is linked and embedded in FreeAPS..."

project = Xcodeproj::Project.open(PROJECT_PATH)
target = project.targets.find { |t| t.name == 'FreeAPS' } or abort '❌ FreeAPS target not found'

# 1) Ensure package reference exists on project
package_ref = project.root_object.package_references.find { |r| r.repositoryURL == SLIDEBUTTON_URL }
unless package_ref
  package_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  package_ref.repositoryURL = SLIDEBUTTON_URL
  req = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference::Requirement)
  req.kind = 'branch'
  req.branch = 'main'
  package_ref.requirement = req
  project.root_object.package_references << package_ref
  puts "✅ Added package reference: #{SLIDEBUTTON_URL}"
end

# 2) Ensure product dependency exists on target
product_dep = target.package_product_dependencies.find { |d| d.product_name == SLIDEBUTTON_PRODUCT }
unless product_dep
  product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
  product_dep.product_name = SLIDEBUTTON_PRODUCT
  product_dep.package = package_ref
  target.package_product_dependencies << product_dep
  puts "✅ Added product dependency to target: #{SLIDEBUTTON_PRODUCT}"
end

# 3) Ensure Embed Frameworks contains SlideButton
embed = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
unless embed
  embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed Frameworks'
  embed.symbol_dst_subfolder_spec = :frameworks
  target.build_phases << embed
end

already = embed.files.any? { |bf| (bf.display_name || bf.file_ref&.display_name).to_s.include?(SLIDEBUTTON_PRODUCT) }
unless already
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = product_dep
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  embed.files << bf
  puts "✅ Embedded SlideButton"
end

project.save
puts "🎉 SlideButton is configured. Now resolve packages and clean build folder."



#!/usr/bin/env ruby

require 'xcodeproj'

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

plugin = project.targets.find { |t| t.name == 'NightscoutServiceKitPlugin' }
abort '❌ NightscoutServiceKitPlugin target not found' unless plugin

# Find Base32 and OneTimePassword product deps
base32_dep = plugin.package_product_dependencies.find { |d| d.product_name == 'Base32' }
otp_dep    = plugin.package_product_dependencies.find { |d| d.product_name == 'OneTimePassword' }

abort '❌ Base32 product dependency missing on plugin' unless base32_dep

# Ensure Embed Frameworks phase exists on plugin
embed = plugin.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
unless embed
  embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed Frameworks'
  embed.symbol_dst_subfolder_spec = :frameworks
  plugin.build_phases << embed
end

def has_embed?(phase, product_dep)
  phase.files.any? do |bf|
    (bf.respond_to?(:product_ref) && bf.product_ref == product_dep) || bf.display_name == product_dep.product_name
  end
end

added = []

unless has_embed?(embed, base32_dep)
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = base32_dep
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  embed.files << bf
  added << 'Base32'
end

if otp_dep && !has_embed?(embed, otp_dep)
  bf2 = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf2.product_ref = otp_dep
  bf2.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  embed.files << bf2
  added << 'OneTimePassword'
end

project.save
puts added.empty? ? 'ℹ️ Nothing to embed' : "✅ Embedded into plugin: #{added.join(', ')}"



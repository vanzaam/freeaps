#!/usr/bin/env ruby

require 'xcodeproj'

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

plugin = project.targets.find { |t| t.name == 'NightscoutServiceKitPlugin' }
abort '❌ NightscoutServiceKitPlugin target not found' unless plugin

removed = []

# 1) Remove package product dependencies Base32 & OneTimePassword from plugin target
plugin.package_product_dependencies.dup.each do |dep|
  if ['Base32', 'OneTimePassword'].include?(dep.product_name)
    plugin.package_product_dependencies.delete(dep)
    removed << "pkg:#{dep.product_name}"
  end
end

# 2) Remove from Frameworks build phase
fw_phase = plugin.frameworks_build_phase
fw_phase.files.dup.each do |bf|
  prod_name = (bf.respond_to?(:product_ref) && bf.product_ref&.product_name) || bf.display_name
  if ['Base32', 'OneTimePassword'].include?(prod_name)
    fw_phase.remove_build_file(bf)
    removed << "fw:#{prod_name}"
  end
end

# 3) Remove from Embed Frameworks build phase
embed_phase = plugin.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
if embed_phase
  embed_phase.files.dup.each do |bf|
    prod_name = (bf.respond_to?(:product_ref) && bf.product_ref&.product_name) || bf.display_name
    if ['Base32', 'OneTimePassword'].include?(prod_name)
      embed_phase.remove_build_file(bf)
      removed << "embed:#{prod_name}"
    end
  end
end

project.save
puts removed.empty? ? 'ℹ️ Nothing to remove from plugin' : "✅ Removed from plugin: #{removed.join(', ')}"



#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
product_name = 'SlideButton'

project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'FreeAPS' } or abort '❌ FreeAPS target not found'

# Ensure embed phase
embed = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
unless embed
  embed = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed.name = 'Embed Frameworks'
  embed.symbol_dst_subfolder_spec = :frameworks
  target.build_phases << embed
end

# Remove ALL SlideButton entries from embed phase
removed = 0
embed.files.dup.each do |bf|
  name = bf.display_name || bf.file_ref&.display_name
  prod_name = (bf.respond_to?(:product_ref) && bf.product_ref && bf.product_ref.respond_to?(:product_name)) ? bf.product_ref.product_name : nil
  if (name && name.include?(product_name)) || (prod_name && prod_name.include?(product_name))
    embed.remove_build_file(bf)
    removed += 1
  end
end

# Find SlideButton product on the FreeAPS target package deps
product_dep = target.package_product_dependencies.find { |d| d.product_name == product_name }
unless product_dep
  puts '⚠️ SlideButton product dependency not found on FreeAPS target; nothing to embed.'
  project.save
  exit 0
end

# Add SINGLE embed entry for SlideButton
bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
bf.product_ref = product_dep
bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
embed.files << bf

project.save
puts "✅ Fixed SlideButton embed (removed #{removed} duplicates, added 1 entry)"



#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'FreeAPS' } or abort '❌ FreeAPS target not found'

embed = target.copy_files_build_phases.find { |p| p.name == 'Embed Frameworks' }
unless embed
  puts 'ℹ️ No Embed Frameworks phase; nothing to purge.'
  exit 0
end

purged = 0
embed.files.dup.each do |bf|
  name = bf.display_name || bf.file_ref&.display_name || bf.file_ref&.name || bf.file_ref&.path
  prod_name = (bf.respond_to?(:product_ref) && bf.product_ref && bf.product_ref.respond_to?(:product_name)) ? bf.product_ref.product_name : nil
  if [name, prod_name].compact.any? { |s| s.to_s.include?('SlideButton') }
    embed.remove_build_file(bf)
    purged += 1
  end
end

project.save
puts "✅ Purged #{purged} SlideButton embed entr(y/ies) from Embed Frameworks"



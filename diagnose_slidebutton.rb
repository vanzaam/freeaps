#!/usr/bin/env ruby

require 'xcodeproj'

project = Xcodeproj::Project.open('FreeAPS.xcodeproj')
target = project.targets.find { |t| t.name == 'FreeAPS' } or abort 'FreeAPS target not found'

puts "Target: #{target.name}"

puts "\nPackage product dependencies:"
target.package_product_dependencies.each_with_index do |d, i|
  mark = d.product_name&.include?('SlideButton') ? ' <-- SlideButton' : ''
  puts "  [#{i}] #{d.product_name}#{mark}"
end

puts "\nFrameworks build phase entries (linking):"
fw = target.frameworks_build_phase
fw.files.each_with_index do |bf, i|
  name = bf.display_name || bf.file_ref&.display_name
  prod_name = (bf.respond_to?(:product_ref) && bf.product_ref && bf.product_ref.respond_to?(:product_name)) ? bf.product_ref.product_name : nil
  mark = (name&.include?('SlideButton') || prod_name&.include?('SlideButton')) ? ' <-- SlideButton' : ''
  puts "  [#{i}] name=#{name.inspect} prod=#{prod_name.inspect}#{mark}"
end

puts "\nCopy files build phases (embedding):"
target.copy_files_build_phases.each_with_index do |phase, pi|
  puts "Phase[#{pi}] name=#{phase.name.inspect} dst=#{phase.symbol_dst_subfolder_spec.inspect}"
  phase.files.each_with_index do |bf, i|
    name = bf.display_name || bf.file_ref&.display_name
    prod_name = (bf.respond_to?(:product_ref) && bf.product_ref && bf.product_ref.respond_to?(:product_name)) ? bf.product_ref.product_name : nil
    mark = (name&.include?('SlideButton') || prod_name&.include?('SlideButton')) ? ' <-- SlideButton' : ''
    puts "    [#{i}] name=#{name.inspect} prod=#{prod_name.inspect} settings=#{bf.settings.inspect}#{mark}"
  end
end



#!/usr/bin/env ruby

require 'xcodeproj'

def find_freeaps_products_root
  base = File.expand_path('~/Library/Developer/Xcode/DerivedData')
  dirs = Dir.glob(File.join(base, 'FreeAPS-*'))
  return nil if dirs.empty?
  # Pick the most recently modified
  dir = dirs.max_by { |d| File.mtime(d) rescue Time.at(0) }
  products = File.join(dir, 'Build', 'Products')
  File.directory?(products) ? products : nil
end

products_root = find_freeaps_products_root
abort '❌ Could not locate FreeAPS DerivedData Build/Products' unless products_root

ns_proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(ns_proj_path)

target_names = ['NightscoutServiceKit', 'NightscoutServiceKitUI']
targets = target_names.map { |n| project.targets.find { |t| t.name == n } }.compact
abort '❌ Targets not found' if targets.empty?

def normalize(value)
  case value
  when nil then []
  when String then [value]
  when Array then value
  else value.to_a
  end
end

updated = false

targets.each do |t|
  t.build_configurations.each do |cfg|
    bs = cfg.build_settings
    # absolute paths for current config/platform
    abs_fw_path = File.join(products_root, cfg.name + '-iphoneos')
    abs_sim_path = File.join(products_root, cfg.name + '-iphonesimulator')

    fw = normalize(bs['FRAMEWORK_SEARCH_PATHS'])
    [abs_fw_path, abs_sim_path].each do |p|
      next unless File.directory?(p)
      unless fw.include?(p)
        fw << p
        updated = true
      end
    end
    bs['FRAMEWORK_SEARCH_PATHS'] = fw

    lib = normalize(bs['LIBRARY_SEARCH_PATHS'])
    [abs_fw_path, abs_sim_path].each do |p|
      next unless File.directory?(p)
      unless lib.include?(p)
        lib << p
        updated = true
      end
    end
    bs['LIBRARY_SEARCH_PATHS'] = lib

    # Linker flags to ensure linking when file refs are absent
    ld = normalize(bs['OTHER_LDFLAGS'])
    %w[-framework LoopKit -framework LoopKitUI].each do |flag|
      unless ld.include?(flag)
        ld << flag
        updated = true
      end
    end
    bs['OTHER_LDFLAGS'] = ld
  end
end

project.save
puts updated ? "✅ Added absolute FreeAPS Build/Products paths and linker flags" : "ℹ️ Absolute paths already present"



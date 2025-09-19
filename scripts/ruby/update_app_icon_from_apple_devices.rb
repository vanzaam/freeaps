#!/usr/bin/env ruby
# coding: utf-8

require 'fileutils'

# This script regenerates AppIcon.appiconset icons using the PNGs already present under apple-devices/AppIcon.appiconset.
# It copies/normalizes filenames into the actual asset catalog used by the project:
#   FreeAPS/Resources/Assets.xcassets/AppIcon.appiconset

ROOT = File.expand_path(File.join(__dir__, '../..'))
src_appicon = File.join(ROOT, 'apple-devices', 'AppIcon.appiconset')
dst_appicon = File.join(ROOT, 'FreeAPS', 'Resources', 'Assets.xcassets', 'AppIcon.appiconset')

abort("❌ Source appicon set not found: #{src_appicon}") unless Dir.exist?(src_appicon)
abort("❌ Destination appicon set not found: #{dst_appicon}") unless Dir.exist?(dst_appicon)

def sh(cmd)
  puts "→ #{cmd}"
  ok = system(cmd)
  abort "❌ Command failed: #{cmd}" unless ok
end

# Ensure sips exists for resizing when necessary
has_sips = system('which sips >/dev/null 2>&1')

# Read destination Contents.json to know the expected filenames and sizes
contents_path = File.join(dst_appicon, 'Contents.json')
contents = File.read(contents_path)

require 'json'
json = JSON.parse(contents)

# Build a map from expected filename -> required size (integer px)
targets = []
json['images'].each do |item|
  filename = item['filename']
  next unless filename && filename.end_with?('.png')
  size_str = item['size'] # like "60x60"
  next unless size_str
  side = size_str.split('x').first.to_f
  scale = (item['scale'] || '1x').sub('x','').to_f
  px = (side * scale).to_i
  targets << [filename, px]
end

# Backup current destination PNGs
timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
backup_dir = File.join(File.dirname(dst_appicon), "AppIcon_backup_#{timestamp}")
FileUtils.mkdir_p(backup_dir)
Dir[File.join(dst_appicon, '*.png')].each do |png|
  FileUtils.cp(png, backup_dir)
end
puts "🗄️  Backed up existing icons to #{backup_dir}"

# Try to locate appropriate source images by matching size in filename from apple-devices set
src_index = {}
Dir[File.join(src_appicon, '*.png')].each do |png|
  base = File.basename(png, '.png')
  # Attempt to parse last number in the filename as size (e.g., icon-ios-60x60@2x -> 120)
  if base =~ /(\d+)(?:x\d+)?(?:@([23])x)?$/
    base_size = $1.to_i
    scale = ($2 || '1').to_i
    px = base_size * scale
    (src_index[px] ||= []) << png
  end
end

updated = 0
missing = []
targets.each do |(filename, px)|
  dst = File.join(dst_appicon, filename)
  source = nil
  # Prefer exact px size match from apple-devices
  candidates = src_index[px] || []
  source = candidates.first if candidates.any?

  if source
    FileUtils.cp(source, dst)
    updated += 1
  elsif has_sips
    # Fallback: pick the largest available from src and downscale
    largest_px, files = src_index.max_by { |k, _| k }
    if largest_px && files && files.any?
      src = files.first
      sh %(sips -s format png -z #{px} #{px} "#{src}" --out "#{dst}")
      updated += 1
    else
      missing << filename
    end
  else
    missing << filename
  end
end

puts "✅ Updated #{updated} icons in destination appicon set"
unless missing.empty?
  puts "⚠️  Missing #{missing.size} icons that could not be generated:"
  missing.each { |f| puts "   - #{f}" }
end

puts "Done. If Xcode shows stale icons, clean build folder and rebuild."



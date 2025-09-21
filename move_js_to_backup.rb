#!/usr/bin/env ruby

require 'xcodeproj'
require 'fileutils'

PROJECT_PATH = 'FreeAPS.xcodeproj'
TARGET_NAME  = 'FreeAPS'
SRC_DIR      = 'FreeAPS/Resources/javascript'
DST_DIR      = '_backup/javascript'

def remove_build_phase_refs(target, file_ref)
  # Remove from resources build phase
  target.resources_build_phase.files.each do |bf|
    if bf.file_ref && bf.file_ref == file_ref
      bf.remove_from_project
    end
  end
  # Also remove from sources if ever added mistakenly
  target.sources_build_phase.files.each do |bf|
    if bf.file_ref && bf.file_ref == file_ref
      bf.remove_from_project
    end
  end
end

puts "🔧 Moving JS resources to #{DST_DIR} and cleaning Xcode project..."

project = Xcodeproj::Project.open(PROJECT_PATH)
target  = project.targets.find { |t| t.name == TARGET_NAME }
abort("❌ Target '#{TARGET_NAME}' not found") unless target

# Ensure destination exists
FileUtils.mkdir_p(DST_DIR)

# Enumerate files on disk
paths = Dir.glob(File.join(SRC_DIR, '**', '*')).select { |p| File.file?(p) }

# Map and remove from project
paths.each do |abs_path|
  rel_path = abs_path
  file_ref = project.files.find { |f| f.path == rel_path || f.real_path.to_s.end_with?(rel_path) rescue false }
  if file_ref
    puts " - Removing project ref: #{file_ref.path}"
    remove_build_phase_refs(target, file_ref)
    file_ref.remove_from_project
  end
end

# Remove the group if exists
group = project.main_group.find_subpath(SRC_DIR, false)
if group
  puts " - Removing group #{SRC_DIR}"
  group.remove_from_project
end

project.save

# Move files physically
Dir.glob(File.join(SRC_DIR, '*')).each do |entry|
  basename = File.basename(entry)
  dest = File.join(DST_DIR, basename)
  if File.exist?(dest)
    # If folder exists, merge
    if File.directory?(entry)
      FileUtils.mkdir_p(dest)
      FileUtils.cp_r(Dir[File.join(entry, '.{*,.*}')].reject { |f| File.basename(f) == '.' || File.basename(f) == '..' }, dest)
      FileUtils.rm_rf(entry)
    else
      FileUtils.mv(entry, dest, force: true)
    end
  else
    FileUtils.mv(entry, dest)
  end
end

puts "✅ JS resources moved. Please clean build folder in Xcode if needed."



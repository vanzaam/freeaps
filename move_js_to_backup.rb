#!/usr/bin/env ruby

require 'xcodeproj'
require 'fileutils'

puts "🗂️  Moving JavaScript resources to backup..."

# Paths
project_path = 'FreeAPS.xcodeproj'
js_source_dir = 'FreeAPS/Resources/javascript'
backup_dir = 'FreeAPS/Resources/_backup'
backup_js_dir = File.join(backup_dir, 'javascript')

# Create backup directory
FileUtils.mkdir_p(backup_dir) unless Dir.exist?(backup_dir)

# Move JavaScript files to backup
if Dir.exist?(js_source_dir)
    if Dir.exist?(backup_js_dir)
        puts "📁 Removing existing backup JavaScript directory..."
        FileUtils.rm_rf(backup_js_dir)
    end
    
    puts "📦 Moving #{js_source_dir} to #{backup_js_dir}..."
    FileUtils.mv(js_source_dir, backup_js_dir)
    puts "✅ JavaScript files moved to backup"
else
    puts "⚠️  JavaScript directory not found: #{js_source_dir}"
end

# Open Xcode project
begin
    project = Xcodeproj::Project.open(project_path)
    
    # Find the main target
    target = project.targets.find { |t| t.name == 'FreeAPS' }
    raise "Target 'FreeAPS' not found!" unless target
    
    # Find Resources build phase
    resources_phase = target.build_phases.find { |phase| phase.class == Xcodeproj::Project::Object::PBXResourcesBuildPhase }
    raise "Resources build phase not found!" unless resources_phase
    
    # Remove JavaScript files from Resources build phase
    js_files_removed = 0
    resources_phase.files.to_a.each do |build_file|
        file_ref = build_file.file_ref
        next unless file_ref
        
        file_path = file_ref.real_path.to_s
        if file_path.include?('javascript') && (file_path.end_with?('.js') || file_path.end_with?('.json'))
            puts "🗑️  Removing from build phase: #{file_path}"
            resources_phase.remove_file_reference(file_ref)
            js_files_removed += 1
        end
    end
    
    # Remove JavaScript file references from project
    js_refs_removed = 0
    project.files.to_a.each do |file_ref|
        file_path = file_ref.real_path.to_s
        if file_path.include?('javascript') && (file_path.end_with?('.js') || file_path.end_with?('.json'))
            puts "🗑️  Removing file reference: #{file_path}"
            file_ref.remove_from_project
            js_refs_removed += 1
        end
    end
    
    # Save project
    project.save
    
    puts "✅ Removed #{js_files_removed} JavaScript files from Resources build phase"
    puts "✅ Removed #{js_refs_removed} JavaScript file references from project"
    puts "✅ Project saved successfully"
    
rescue => e
    puts "❌ Error processing Xcode project: #{e.message}"
    puts e.backtrace.first(5)
    exit 1
end

puts "🎉 JavaScript resources successfully moved to backup and removed from build!"
puts "📁 JavaScript files are now in: #{backup_js_dir}"
puts "🚀 The app will no longer use JavaScript engine when USE_LOOP_ENGINE=YES"
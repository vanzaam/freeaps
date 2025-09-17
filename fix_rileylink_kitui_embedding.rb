#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Fixing RileyLinkKitUI framework embedding..."

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Найти FreeAPS target
target = project.targets.find { |t| t.name == 'FreeAPS' }

if target.nil?
  puts "❌ FreeAPS target not found!"
  exit 1
end

puts "✅ Found FreeAPS target"

# Найти Build Phase для Embed Frameworks
embed_phase = target.copy_files_build_phases.find do |phase|
  phase.name == 'Embed Frameworks'
end

if embed_phase.nil?
  puts "❌ Embed Frameworks phase not found!"
  exit 1
end

puts "✅ Found Embed Frameworks phase"

# Проверить, уже ли добавлен RileyLinkKitUI
already_embedded = embed_phase.files.any? do |file|
  file.display_name&.include?('RileyLinkKitUI') || 
  file.file_ref&.display_name&.include?('RileyLinkKitUI')
end

if already_embedded
  puts "✅ RileyLinkKitUI already in Embed Frameworks"
else
  puts "🔍 Searching for RileyLinkKitUI.framework reference..."
  
  # Найти RileyLinkKitUI framework reference
  rileylink_kitui_ref = nil
  
  # Поиск среди всех файловых ссылок
  project.files.each do |file_ref|
    if file_ref.display_name == 'RileyLinkKitUI.framework'
      rileylink_kitui_ref = file_ref
      puts "✅ Found RileyLinkKitUI.framework reference: #{file_ref.display_name}"
      break
    end
  end
  
  # Если не найден, попробуем добавить ссылку на framework из workspace
  if rileylink_kitui_ref.nil?
    puts "📦 Creating reference to RileyLinkKitUI.framework..."
    
    # Создать файловую ссылку на RileyLinkKitUI.framework
    rileylink_kitui_ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
    rileylink_kitui_ref.name = 'RileyLinkKitUI.framework'
    rileylink_kitui_ref.path = 'RileyLinkKitUI.framework'
    rileylink_kitui_ref.source_tree = 'BUILT_PRODUCTS_DIR'
    rileylink_kitui_ref.explicit_file_type = 'wrapper.framework'
    rileylink_kitui_ref.include_in_index = false
    
    # Добавить в группу Frameworks
    frameworks_group = project.frameworks_group
    frameworks_group.children << rileylink_kitui_ref
    
    puts "✅ Created RileyLinkKitUI.framework reference"
  end
  
  # Добавить в Frameworks build phase (для linking)
  frameworks_phase = target.frameworks_build_phase
  unless frameworks_phase.files.any? { |f| f.file_ref == rileylink_kitui_ref }
    build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    build_file.file_ref = rileylink_kitui_ref
    frameworks_phase.files << build_file
    puts "✅ Added RileyLinkKitUI to Frameworks (linking)"
  end
  
  # Добавить в Embed Frameworks build phase (для embedding)
  puts "📦 Adding RileyLinkKitUI to Embed Frameworks..."
  
  embed_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  embed_build_file.file_ref = rileylink_kitui_ref
  embed_build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
  
  embed_phase.files << embed_build_file
  puts "✅ Added RileyLinkKitUI to Embed Frameworks"
end

# Сохранить проект
project.save
puts "✅ Project saved successfully!"

# Очистить derived data
puts "🧹 Cleaning derived data..."
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")

puts ""
puts "🎉 RileyLinkKitUI embedding fix completed!"
puts ""
puts "Next steps:"
puts "1. Clean Build Folder in Xcode (Cmd+Shift+K)"
puts "2. Build and run the project on device"
puts "3. RileyLinkKitUI dyld loading error should be resolved"

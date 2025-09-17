#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Fixing missing framework embedding issues..."

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

# Список framework'ов, которые должны быть встроены
required_frameworks = [
  'SwiftCharts',
  'RileyLinkKitUI'
]

frameworks_added = []

required_frameworks.each do |framework_name|
  puts "🔍 Checking #{framework_name}..."
  
  # Проверить, уже ли добавлен framework
  already_embedded = embed_phase.files.any? do |file|
    file.display_name&.include?(framework_name) || 
    file.file_ref&.display_name&.include?(framework_name)
  end
  
  if already_embedded
    puts "✅ #{framework_name} already in Embed Frameworks"
    next
  end
  
  # Найти framework reference
  framework_ref = nil
  
  # Сначала попробуем найти среди Swift Package dependencies
  target.package_product_dependencies.each do |dep|
    if dep.product_name == framework_name
      framework_ref = dep
      break
    end
  end
  
  # Если не найден среди package dependencies, ищем среди файловых ссылок
  if framework_ref.nil?
    project.files.each do |file_ref|
      if file_ref.display_name&.include?(framework_name) && 
         file_ref.display_name&.include?('.framework')
        framework_ref = file_ref
        break
      end
    end
  end
  
  if framework_ref.nil?
    puts "⚠️  #{framework_name} reference not found, skipping..."
    next
  end
  
  puts "📦 Adding #{framework_name} to Embed Frameworks..."
  
  # Создать build file для embedding
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = framework_ref if framework_ref.respond_to?(:product_name)
  build_file.file_ref = framework_ref unless framework_ref.respond_to?(:product_name)
  build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  
  # Добавить в embed phase
  embed_phase.files << build_file
  
  frameworks_added << framework_name
  puts "✅ Added #{framework_name} to Embed Frameworks"
end

# Сохранить проект
project.save
puts "✅ Project saved successfully!"

# Очистить derived data
puts "🧹 Cleaning derived data..."
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")

# Разрешить зависимости
puts "📦 Resolving dependencies..."
system("xcodebuild -workspace FreeAPS.xcworkspace -scheme 'FreeAPS X' -resolvePackageDependencies")

puts ""
puts "🎉 Framework embedding fix completed!"
if frameworks_added.any?
  puts "✅ Added frameworks: #{frameworks_added.join(', ')}"
else
  puts "ℹ️  All frameworks were already properly embedded"
end

puts ""
puts "Next steps:"
puts "1. Clean Build Folder in Xcode (Cmd+Shift+K)"
puts "2. Build and run the project on device"
puts "3. The dyld loading errors should be resolved"


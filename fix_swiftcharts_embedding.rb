#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Fixing SwiftCharts embedding issue..."

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

# Найти SwiftCharts в dependencies
swift_charts_ref = nil
target.package_product_dependencies.each do |dep|
  if dep.product_name == 'SwiftCharts'
    swift_charts_ref = dep
    break
  end
end

if swift_charts_ref.nil?
  puts "❌ SwiftCharts dependency not found!"
  exit 1
end

puts "✅ Found SwiftCharts dependency"

# Найти Build Phase для Embed Frameworks
embed_phase = target.copy_files_build_phases.find do |phase|
  phase.name == 'Embed Frameworks'
end

if embed_phase.nil?
  puts "❌ Embed Frameworks phase not found!"
  exit 1
end

puts "✅ Found Embed Frameworks phase"

# Проверить, уже ли добавлен SwiftCharts
already_embedded = embed_phase.files.any? do |file|
  file.display_name&.include?('SwiftCharts')
end

if already_embedded
  puts "✅ SwiftCharts already in Embed Frameworks"
else
  puts "📦 Adding SwiftCharts to Embed Frameworks..."
  
  # Создать build file для embedding
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.product_ref = swift_charts_ref
  build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy'] }
  
  # Добавить в embed phase
  embed_phase.files << build_file
  
  puts "✅ Added SwiftCharts to Embed Frameworks"
end

# Сохранить проект
project.save
puts "✅ Project saved successfully!"

puts ""
puts "Next steps:"
puts "1. Clean Build Folder in Xcode (Cmd+Shift+K)"
puts "2. Build and run the project"

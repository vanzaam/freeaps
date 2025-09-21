#!/usr/bin/env ruby

require 'xcodeproj'

puts "🧹 Удаляем ссылки на старые модули Home и AddCarbs..."

# Открываем проект
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Находим target FreeAPS
target = project.targets.find { |t| t.name == 'FreeAPS' }
raise "Target FreeAPS не найден!" unless target

# Список файлов для удаления
files_to_remove = [
  # Home модуль
  'FreeAPS/Sources/Modules/Home/HomeStateModel.swift',
  'FreeAPS/Sources/Modules/Home/View/Header/PumpView.swift',
  'FreeAPS/Sources/Modules/Home/HomeProvider.swift',
  'FreeAPS/Sources/Modules/Home/View/COBDetailView.swift',
  'FreeAPS/Sources/Modules/Home/HomeDataFlow.swift',
  'FreeAPS/Sources/Modules/Home/View/Header/LoopView.swift',
  'FreeAPS/Sources/Modules/Home/View/HomeRootView.swift',
  'FreeAPS/Sources/Modules/Home/View/Chart/MainChartView.swift',
  'FreeAPS/Sources/Modules/Home/View/Header/CurrentGlucoseView.swift',
  
  # AddCarbs модуль
  'FreeAPS/Sources/Modules/AddCarbs/AddCarbsDataFlow.swift',
  'FreeAPS/Sources/Modules/AddCarbs/AddCarbsProvider.swift',
  'FreeAPS/Sources/Modules/AddCarbs/AddCarbsStateModel.swift',
  'FreeAPS/Sources/Modules/AddCarbs/View/AddCarbsRootView.swift'
]

removed_count = 0

files_to_remove.each do |file_path|
  puts "🗑️  Ищем файл: #{file_path}"
  
  # Находим file reference
  file_ref = project.files.find { |f| f.path == file_path }
  
  if file_ref
    puts "   ✅ Найден, удаляем..."
    
    # Удаляем из build phases
    target.source_build_phase.remove_file_reference(file_ref)
    
    # Удаляем file reference
    file_ref.remove_from_project
    
    removed_count += 1
    puts "   ✅ Удален: #{file_path}"
  else
    puts "   ⚠️  Не найден: #{file_path}"
  end
end

# Сохраняем проект
project.save

puts ""
puts "✅ Готово! Удалено #{removed_count} файлов из проекта"
puts "📁 Файлы физически перемещены в _backup/old_openaps_screens/"
puts ""
puts "Теперь можно пересобирать проект!"


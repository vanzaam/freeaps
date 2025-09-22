#!/usr/bin/env ruby

require 'xcodeproj'

puts "🧹 Очистка ссылок на старый InsulinCurveEditor.swift..."

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Находим таргет FreeAPS
target = project.targets.find { |target| target.name == 'FreeAPS' }
raise "Target FreeAPS не найден!" unless target

# Ищем ссылки на удаленный файл
files_to_remove = []
project.files.each do |file|
  if file.path && file.path.include?('InsulinCurveEditor.swift')
    files_to_remove << file
    puts "🗑️  Найден файл для удаления: #{file.path}"
  end
end

# Удаляем ссылки на файлы
files_to_remove.each do |file|
  # Удаляем из build phases
  target.build_phases.each do |phase|
    if phase.respond_to?(:files)
      phase.files.delete_if { |build_file| build_file.file_ref == file }
    end
  end
  
  # Удаляем из проекта
  file.remove_from_project
  puts "✅ Удалена ссылка на #{file.path}"
end

# Сохраняем проект
project.save

puts "🎯 Очистка завершена!"
puts "📊 Удалено ссылок: #{files_to_remove.count}"
puts ""
puts "🚀 Теперь используется только новый интерактивный редактор кривой инсулина!"
puts "✨ С реальными формулами OpenAPS и визуализацией в реальном времени!"

#!/usr/bin/env ruby

require 'xcodeproj'

puts "🧹 Cleaning old chart files from Xcode project..."

# Открыть проект
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Файлы для удаления
files_to_remove = [
    'LoopKitChartView.swift',
    'InteractiveLoopChart.swift'
]

files_to_remove.each do |filename|
    # Найти все ссылки на файл
    file_references = project.files.select { |file| file.path == filename }
    
    file_references.each do |file_ref|
        puts "🗑️ Removing file reference: #{file_ref.path}"
        
        # Удалить из build phases всех таргетов
        project.targets.each do |target|
            target.source_build_phase.files.each do |build_file|
                if build_file.file_ref == file_ref
                    puts "  ➜ Removing from build phase: #{target.name}"
                    target.source_build_phase.files.delete(build_file)
                end
            end
        end
        
        # Удалить файл из проекта
        file_ref.remove_from_project
    end
end

# Сохранить проект
project.save

puts "✅ Successfully cleaned old chart files from project"
puts "🎯 Files removed: #{files_to_remove.join(', ')}"

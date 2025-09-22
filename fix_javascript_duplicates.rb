#!/usr/bin/env ruby

require 'xcodeproj'

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Найдем target FreeAPS
target = project.targets.find { |target| target.name == 'FreeAPS' }
if !target
    puts "❌ Target FreeAPS не найден!"
    exit 1
end

# Удаляем все JavaScript файлы из Copy Bundle Resources
build_phase = target.resources_build_phase
files_to_remove = build_phase.files.select do |build_file|
    build_file.file_ref && build_file.file_ref.path && build_file.file_ref.path.end_with?('.js')
end

files_to_remove.each do |build_file|
    puts "🗑️ Удаляем дублированный файл: #{build_file.file_ref.path}"
    build_phase.remove_build_file(build_file)
end

# Удаляем группу javascript из проекта
resources_group = project.main_group.find_subpath('FreeAPS/Resources', false)
if resources_group
    javascript_group = resources_group.find_subpath('javascript', false)
    if javascript_group
        puts "🗑️ Удаляем группу javascript из проекта"
        resources_group.remove_reference(javascript_group)
    end
end

# Сохраняем проект
project.save

puts "✅ Очистка дублированных JavaScript файлов завершена!"

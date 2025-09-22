#!/usr/bin/env ruby

require 'xcodeproj'

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Найдем группу Resources
resources_group = project.main_group.find_subpath('FreeAPS/Resources', false)
if !resources_group
    puts "❌ Группа FreeAPS/Resources не найдена!"
    exit 1
end

# Создаем группу javascript
javascript_group = resources_group.find_subpath('javascript', true)

# Создаем подгруппы
bundle_group = javascript_group.find_subpath('bundle', true)
prepare_group = javascript_group.find_subpath('prepare', true)  
middleware_group = javascript_group.find_subpath('middleware', true)

# Добавляем файлы из bundle/
bundle_files = [
    'autosens.js',
    'autotune-core.js', 
    'autotune-prep.js',
    'basal-set-temp.js',
    'determine-basal.js',
    'glucose-get-last.js',
    'iob.js',
    'profile.js'
]

bundle_files.each do |filename|
    file_ref = bundle_group.new_file("FreeAPS/Resources/javascript/bundle/#{filename}")
    file_ref.last_known_file_type = 'text'
end

# Добавляем файлы из prepare/
prepare_files = [
    'autosens.js',
    'autotune-core.js',
    'autotune-prep.js', 
    'determine-basal.js',
    'iob.js',
    'log.js',
    'meal.js',
    'profile.js'
]

prepare_files.each do |filename|
    file_ref = prepare_group.new_file("FreeAPS/Resources/javascript/prepare/#{filename}")
    file_ref.last_known_file_type = 'text'
end

# Добавляем файлы из middleware/
middleware_files = [
    'determine_basal.js'
]

middleware_files.each do |filename|
    file_ref = middleware_group.new_file("FreeAPS/Resources/javascript/middleware/#{filename}")
    file_ref.last_known_file_type = 'text'
end

# Находим target FreeAPS
target = project.targets.find { |target| target.name == 'FreeAPS' }
if !target
    puts "❌ Target FreeAPS не найден!"
    exit 1
end

# Добавляем все JavaScript файлы в Copy Bundle Resources
build_phase = target.resources_build_phase
javascript_group.recursive_children.each do |file_ref|
    if file_ref.is_a?(Xcodeproj::Project::Object::PBXFileReference)
        build_file = build_phase.add_file_reference(file_ref)
        puts "📄 Добавлен в Bundle Resources: #{file_ref.path}"
    end
end

# Сохраняем проект
project.save

puts "✅ Успешно добавлены JavaScript алгоритмы OpenAPS в проект!"
puts "📊 Добавлено файлов:"
puts "   Bundle: #{bundle_files.count}"
puts "   Prepare: #{prepare_files.count}"  
puts "   Middleware: #{middleware_files.count}"
puts "   Всего: #{bundle_files.count + prepare_files.count + middleware_files.count}"

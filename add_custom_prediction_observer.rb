#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Adding CustomPredictionObserver.swift to FreeAPS project..."

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Группа для протоколов
protocols_group = project.main_group.find_subpath('FreeAPS/Sources/Protocols', true)

# Добавляем CustomPredictionObserver.swift
observer_file = protocols_group.new_file('CustomPredictionObserver.swift')
observer_target = project.targets.find { |target| target.name == 'FreeAPS' }
observer_target.add_file_references([observer_file])

# Сохраняем проект
project.save

puts "✅ Успешно добавлен файл CustomPredictionObserver.swift в проект"

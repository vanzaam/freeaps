#!/usr/bin/env ruby

require 'xcodeproj'

puts "🧮 Добавляем Custom IOB Calculator в проект..."

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Группа для новых файлов
services_group = project.main_group.find_subpath('FreeAPS/Sources/Services', true)
iob_group = services_group.find_subpath('IOB', true)

# Добавляем CustomIOBCalculator.swift
calculator_file = iob_group.new_file('CustomIOBCalculator.swift')
calculator_target = project.targets.find { |target| target.name == 'FreeAPS' }
calculator_target.add_file_references([calculator_file])

# Сохраняем проект
project.save

puts "✅ Успешно добавлен CustomIOBCalculator.swift в проект"

# Исправляем зависимости Swift Package Manager
puts "📦 Исправляем зависимости..."
system("xcodebuild -resolvePackageDependencies")
puts "🧹 Очищаем derived data..."
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")

puts "🎉 Готово! Custom IOB Calculator добавлен в проект"

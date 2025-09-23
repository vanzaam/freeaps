#!/usr/bin/env ruby

require 'xcodeproj'

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Находим папку Services
services_group = project.main_group.find_subpath('FreeAPS/Sources/Services', true)

# Создаем новую подгруппу Predictions
predictions_group = services_group.new_group('Predictions')

# Добавляем CustomPredictionService.swift
prediction_service_file = predictions_group.new_file('CustomPredictionService.swift')
prediction_service_target = project.targets.find { |target| target.name == 'FreeAPS' }
prediction_service_target.add_file_references([prediction_service_file])

# Сохраняем проект
project.save

puts "✅ Успешно добавлены файлы Custom Prediction Service в проект:"
puts "  - FreeAPS/Sources/Services/Predictions/CustomPredictionService.swift"
puts ""
puts "🎯 Custom Prediction Service создан для:"
puts "  • Использования oref0 напрямую с правильными IOB данными"
puts "  • Создания корректных прогнозов predBGs"
puts "  • Замены сломанных системных прогнозов"
puts ""
puts "🚀 Следующие шаги:"
puts "  1. Скомпилировать проект"
puts "  2. Интегрировать сервис с основной логикой"
puts "  3. Протестировать правильность прогнозов"

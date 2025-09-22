#!/usr/bin/env ruby

require 'xcodeproj'

puts "🚀 Добавляем систему прогнозирования IOB в OpenAPS..."

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Находим таргет FreeAPS
target = project.targets.find { |target| target.name == 'FreeAPS' }
raise "Target FreeAPS не найден!" unless target

# Создаем группы и добавляем файлы
services_group = project.main_group.find_subpath('FreeAPS/Sources/Services', true)
iob_predictor_group = services_group.new_group('IOBPredictor')

dashboard_view_group = project.main_group.find_subpath('FreeAPS/Sources/Modules/Dashboard/View', true)

# Добавляем IOBPredictorService.swift
iob_service_file = iob_predictor_group.new_file('IOBPredictorService.swift')
target.add_file_references([iob_service_file])

# Добавляем IOBForecastView.swift  
iob_view_file = dashboard_view_group.new_file('IOBForecastView.swift')
target.add_file_references([iob_view_file])

# Сохраняем проект
project.save

puts "✅ Система прогнозирования IOB успешно добавлена!"
puts ""
puts "📊 Добавленные компоненты:"
puts "• IOBPredictorService.swift - сервис прогнозирования IOB"
puts "• IOBForecastView.swift - компонент отображения на главном экране"
puts ""
puts "🎯 Особенности системы прогнозирования IOB:"
puts "• ⏱️  Прогноз с интервалом 5 минут на 6 часов вперед"
puts "• 🧮 Использует точные формулы кривой инсулина из настроек"
puts "• 📈 Визуализация IOB и активности в реальном времени"
puts "• 🔄 Автоматическое обновление каждые 30 секунд"
puts "• 📱 Интегрирован в главный экран Dashboard"
puts "• 🎛️ Переключение между 1ч, 3ч, 6ч временными окнами"
puts "• 🔍 Ключевые точки прогноза с цветовой индикацией"
puts "• ⚡ Определение пика активности инсулина"
puts ""
puts "🔧 Технические детали:"
puts "• Использует ExponentialInsulinModel из LoopKit"
puts "• Настройки кривой загружаются из InteractiveInsulinCurveEditor"
puts "• Обрабатывает болюсы и временные базалы"
puts "• Dependency Injection через Swinject"
puts "• Реактивное программирование с Combine"
puts ""
puts "🎉 Теперь пользователи видят точный прогноз IOB в реальном времени!"

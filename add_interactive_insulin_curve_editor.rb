#!/usr/bin/env ruby

require 'xcodeproj'

puts "🚀 Добавляем интерактивный редактор кривой инсулина..."

# Путь к проекту
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Находим группу для views
views_group = project.main_group.find_subpath('FreeAPS/Sources/Modules/PumpConfig/View', true)

# Добавляем новый файл
insulin_curve_file = views_group.new_file('InteractiveInsulinCurveEditor.swift')

# Находим таргет FreeAPS
target = project.targets.find { |target| target.name == 'FreeAPS' }
raise "Target FreeAPS не найден!" unless target

# Добавляем файл к таргету
target.add_file_references([insulin_curve_file])

# Сохраняем проект
project.save

puts "✅ Файл InteractiveInsulinCurveEditor.swift успешно добавлен в проект!"
puts ""
puts "📊 Особенности нового редактора:"
puts "• Интерактивные слайдеры для настройки параметров"
puts "• Реальные формулы OpenAPS для расчета кривых"
puts "• Визуализация IOB и активности в реальном времени"
puts "• Поддержка Rapid-Acting, Ultra-Rapid (Fiasp) и Custom кривых"
puts "• Точные параметры: Rapid (75мин), Ultra-Rapid (55мин)"
puts ""
puts "🎯 Формула OpenAPS (экспоненциальная модель):"
puts "τ = peakTime × (1 - peakTime/duration) / (1 - 2×peakTime/duration)"
puts "a = 2×τ / duration"
puts "S = 1 / (1 - a + (1 + a) × exp(-duration/τ))"
puts "IOB(t) = 1 - S × (1-a) × ((t²/(τ×DIA×(1-a)) - t/τ - 1) × e^(-t/τ) + 1)"
puts ""
puts "🔗 Для интеграции в приложение:"
puts "1. Добавьте кнопку в PumpConfig для запуска редактора"
puts "2. Используйте InteractiveInsulinCurveEditor() в NavigationLink"
puts "3. Настройки автоматически сохраняются в FileStorage"

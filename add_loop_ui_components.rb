#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Adding Loop UI components to Xcode project..."

# Открыть проект
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Найти группу Dashboard/View
dashboard_group = project.main_group.find_subpath('FreeAPS/Sources/Modules/Dashboard/View', true)

# Добавить новые файлы
files_to_add = [
    'LoopStatusHUDView.swift',
    'LoopActionButtonsView.swift'
]

target = project.targets.find { |t| t.name == 'FreeAPS' }

files_to_add.each do |filename|
    file_ref = dashboard_group.new_file(filename)
    target.add_file_references([file_ref])
    puts "✅ Added #{filename}"
end

# Сохранить проект
project.save

puts "✅ Successfully added Loop UI components to project"
puts "📁 Group: FreeAPS/Sources/Modules/Dashboard/View"
puts "🎯 Target: FreeAPS"

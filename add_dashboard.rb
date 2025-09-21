#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Adding Dashboard files to Xcode project..."

# 1. Clean environment
puts "🧹 Cleaning derived data..."
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")

# 2. Open project
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 3. Find target
target = project.targets.find { |t| t.name == 'FreeAPS' }
raise "Target not found!" unless target

# 4. Create Dashboard group
modules_group = project.main_group.find_subpath('FreeAPS/Sources/Modules', true)
dashboard_group = modules_group.find_subpath('Dashboard', true) || modules_group.new_group('Dashboard')
view_group = dashboard_group.find_subpath('View', true) || dashboard_group.new_group('View')
charts_group = dashboard_group.find_subpath('Charts', true) || dashboard_group.new_group('Charts')

# 5. Add files to project
files_to_add = [
  'FreeAPS/Sources/Modules/Dashboard/View/DashboardRootView.swift',
  'FreeAPS/Sources/Modules/Dashboard/Charts/LoopStyleMainChartView.swift',
  'FreeAPS/Sources/Modules/Dashboard/DashboardStateModel.swift'
]

files_to_add.each do |file_path|
  # Check if file exists
  unless File.exist?(file_path)
    puts "❌ File not found: #{file_path}"
    next
  end
  
  # Determine group based on file path
  group = if file_path.include?('/Charts/')
    charts_group
  else
    view_group
  end
  
  # Add file reference
  file_ref = group.new_file(file_path)
  
  # Add to target
  target.add_file_references([file_ref])
  
  puts "✅ Added: #{file_path}"
end

# 6. Save project
project.save

# 7. Resolve dependencies
puts "📦 Resolving dependencies..."
system("xcodebuild -resolvePackageDependencies")

puts "✅ Dashboard files successfully added to project!"
puts "📝 Next steps:"
puts "   1. Build project in Xcode"
puts "   2. Test DashboardRootView"
puts "   3. Create configuration flags (Stage 4)"

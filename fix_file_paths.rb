#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Fixing file paths in Xcode project..."

# 1. Clean environment
puts "🧹 Cleaning derived data..."
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")

# 2. Open project
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 3. Find target
target = project.targets.find { |t| t.name == 'FreeAPS' }
raise "Target not found!" unless target

# 4. Remove files with incorrect paths
files_to_remove = [
  'FreeAPS/Sources/Modules/FreeAPS/Sources/Modules/AddCarbsLoop/View/AddCarbsLoopView.swift',
  'FreeAPS/Sources/Modules/FreeAPS/Sources/Modules/AddCarbsLoop/AddCarbsLoopViewModel.swift',
  'FreeAPS/Sources/Modules/FreeAPS/Sources/Modules/Dashboard/View/DashboardRootView.swift',
  'FreeAPS/Sources/Modules/FreeAPS/Sources/Modules/Dashboard/Charts/LoopStyleMainChartView.swift',
  'FreeAPS/Sources/Modules/FreeAPS/Sources/Modules/Dashboard/DashboardStateModel.swift'
]

files_to_remove.each do |file_path|
  # Find and remove file reference
  file_ref = project.files.find { |f| f.path == file_path }
  if file_ref
    file_ref.remove_from_project
    puts "❌ Removed incorrect path: #{file_path}"
  end
end

# 5. Add files with correct paths
files_to_add = [
  'FreeAPS/Sources/Modules/AddCarbsLoop/View/AddCarbsLoopView.swift',
  'FreeAPS/Sources/Modules/AddCarbsLoop/AddCarbsLoopViewModel.swift',
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
  if file_path.include?('/AddCarbsLoop/')
    group = project.main_group.find_subpath('FreeAPS/Sources/Modules/AddCarbsLoop', true)
    if file_path.include?('/View/')
      group = group.find_subpath('View', true) || group.new_group('View')
    end
  elsif file_path.include?('/Dashboard/')
    group = project.main_group.find_subpath('FreeAPS/Sources/Modules/Dashboard', true)
    if file_path.include?('/View/')
      group = group.find_subpath('View', true) || group.new_group('View')
    elsif file_path.include?('/Charts/')
      group = group.find_subpath('Charts', true) || group.new_group('Charts')
    end
  else
    group = project.main_group
  end
  
  # Add file reference
  file_ref = group.new_file(file_path)
  
  # Add to target
  target.add_file_references([file_ref])
  
  puts "✅ Added correct path: #{file_path}"
end

# 6. Save project
project.save

# 7. Resolve dependencies
puts "📦 Resolving dependencies..."
system("xcodebuild -resolvePackageDependencies")

# Remove any refs with duplicated path segment
DUP_SEGMENT = 'FreeAPS/Sources/Modules/FreeAPS/Sources/Modules'

bad_refs = project.files.select { |f| f.path && f.path.include?(DUP_SEGMENT) }

bad_refs.each do |ref|
  project.objects.select { |o| o.isa == 'PBXBuildFile' && o.file_ref == ref }.each do |bf|
    bf.remove_from_project
  end
  puts "❌ Removed incorrect ref: #{ref.path}"
  ref.remove_from_project
end

# Save the cleaned project
project.save

puts "✅ File references cleaned. Now reopen Xcode and build."

#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Adding Carb UI files to Xcode project..."

# 1. Clean environment
puts "🧹 Cleaning derived data..."
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")

# 2. Open project
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 3. Find target
target = project.targets.find { |t| t.name == 'FreeAPS' }
raise "Target not found!" unless target

# 4. Create AddCarbsLoop group
modules_group = project.main_group.find_subpath('FreeAPS/Sources/Modules', true)
add_carbs_group = modules_group.find_subpath('AddCarbsLoop', true) || modules_group.new_group('AddCarbsLoop')
view_group = add_carbs_group.find_subpath('View', true) || add_carbs_group.new_group('View')

# 5. Add files to project
files_to_add = [
  'FreeAPS/Sources/Modules/AddCarbsLoop/View/AddCarbsLoopView.swift',
  'FreeAPS/Sources/Modules/AddCarbsLoop/AddCarbsLoopViewModel.swift'
]

files_to_add.each do |file_path|
  # Check if file exists
  unless File.exist?(file_path)
    puts "❌ File not found: #{file_path}"
    next
  end
  
  # Add file reference
  file_ref = view_group.new_file(file_path)
  
  # Add to target
  target.add_file_references([file_ref])
  
  puts "✅ Added: #{file_path}"
end

# 6. Save project
project.save

# 7. Resolve dependencies
puts "📦 Resolving dependencies..."
system("xcodebuild -resolvePackageDependencies")

puts "✅ Carb UI files successfully added to project!"
puts "📝 Next steps:"
puts "   1. Build project in Xcode"
puts "   2. Test AddCarbsLoopView"
puts "   3. Create Dashboard view (Stage 3)"

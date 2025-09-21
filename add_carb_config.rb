#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Adding Carb Configuration files to Xcode project..."

# 1. Clean environment
puts "🧹 Cleaning derived data..."
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")

# 2. Open project
project_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 3. Find target
target = project.targets.find { |t| t.name == 'FreeAPS' }
raise "Target not found!" unless target

# 4. Add files to Services/Carbs group
services_group = project.main_group.find_subpath('FreeAPS/Sources/Services', true)
carbs_group = services_group.find_subpath('Carbs', true)

# 5. Add files to project
files_to_add = [
  'FreeAPS/Sources/Services/Carbs/CarbConfigurationService.swift',
  'FreeAPS/Sources/Services/Carbs/CarbIntegrationAdapter.swift'
]

files_to_add.each do |file_path|
  # Check if file exists
  unless File.exist?(file_path)
    puts "❌ File not found: #{file_path}"
    next
  end
  
  # Add file reference
  file_ref = carbs_group.new_file(file_path)
  
  # Add to target
  target.add_file_references([file_ref])
  
  puts "✅ Added: #{file_path}"
end

# 6. Save project
project.save

# 7. Resolve dependencies
puts "📦 Resolving dependencies..."
system("xcodebuild -resolvePackageDependencies")

puts "✅ Carb Configuration files successfully added to project!"
puts "📝 Next steps:"
puts "   1. Build project in Xcode"
puts "   2. Test configuration switching"
puts "   3. Create SMB adaptation (Stage 5)"

#!/usr/bin/env ruby

require 'xcodeproj'

puts "🔧 Adding FormatterCache to OmniBLE..."

# 1. Clean environment
puts "🧹 Cleaning derived data..."
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")

# 2. Open OmniBLE project
project_path = 'Dependencies/OmniBLE/OmniBLE.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# 3. Find target
target = project.targets.find { |t| t.name == 'OmniBLE' }
raise "OmniBLE target not found!" unless target

# 4. Create Utils group if it doesn't exist
utils_group = project.main_group.find_subpath('OmniBLE/Utils', true)

# 5. Add FormatterCache.swift to project
formatter_cache_file = utils_group.new_file('FormatterCache.swift')
target.add_file_references([formatter_cache_file])

# 6. Save project
project.save

puts "✅ FormatterCache successfully added to OmniBLE project!"

# 7. Resolve dependencies
puts "📦 Resolving dependencies..."
system("xcodebuild -resolvePackageDependencies")

puts "🎉 OmniBLE FormatterCache setup complete!"

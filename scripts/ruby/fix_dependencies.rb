#!/usr/bin/env ruby

puts "🔧 Fixing OpenAPS Swift Package Manager dependencies..."

# 1. Clean FreeAPS derived data first
puts "🧹 Cleaning FreeAPS derived data..."
system("rm -rf ~/Library/Developer/Xcode/DerivedData/FreeAPS*")

# 2. Try resolving with workspace and scheme
puts "📦 Resolving package dependencies with workspace..."
result = system("xcodebuild -workspace FreeAPS.xcworkspace -scheme 'OpenAPS' -resolvePackageDependencies")

if !result
  puts "⚠️  Workspace resolution failed, trying project resolution..."
  system("xcodebuild -project FreeAPS.xcodeproj -resolvePackageDependencies")
end

# 3. Check if LibreTransmitter framework is accessible
puts "🔍 Checking LibreTransmitter framework..."
if File.exist?("Dependencies/LibreTransmitter/RawGlucose.xcframework/Info.plist")
  puts "✅ RawGlucose.xcframework found"
else
  puts "❌ RawGlucose.xcframework missing or corrupted"
end

puts "✅ Dependencies fix completed!"
puts ""
puts "Next steps:"
puts "1. Open Xcode if not already open: open FreeAPS.xcworkspace"
puts "2. Clean Build Folder: Product -> Clean Build Folder (Cmd+Shift+K)"
puts "3. Build the project: Product -> Build (Cmd+B)"

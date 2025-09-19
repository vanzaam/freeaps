#!/usr/bin/env ruby

ws_path = 'FreeAPS.xcworkspace/contents.xcworkspacedata'
xml = File.read(ws_path)

before = xml.dup
xml = xml.gsub(/\s*<FileRef\s+location\s*=\s*"group:Dependencies\/NightscoutService\/NightscoutService\.xcodeproj"\s*>\s*<\/FileRef>\s*/m, "")

if xml != before
  File.write(ws_path, xml)
  puts '✅ Removed NightscoutService.xcodeproj from workspace'
else
  puts 'ℹ️ NightscoutService.xcodeproj was not present in workspace (no change)'
end


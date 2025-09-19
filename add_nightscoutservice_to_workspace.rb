#!/usr/bin/env ruby

path = 'FreeAPS.xcworkspace/contents.xcworkspacedata'
xml = File.read(path)
ref = "   <FileRef\n      location = \"group:Dependencies/NightscoutService/NightscoutService.xcodeproj\">\n   </FileRef>\n"

unless xml.include?('Dependencies/NightscoutService/NightscoutService.xcodeproj')
  xml = xml.sub("</Workspace>\n", "#{ref}</Workspace>\n")
  File.write(path, xml)
  puts '✅ Added NightscoutService.xcodeproj to workspace'
else
  puts 'ℹ️ NightscoutService.xcodeproj already in workspace'
end



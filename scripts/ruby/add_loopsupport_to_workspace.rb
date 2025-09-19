#!/usr/bin/env ruby

path = 'FreeAPS.xcworkspace/contents.xcworkspacedata'
xml = File.read(path)
ref = "   <FileRef\n      location = \"group:Dependencies/LoopSupport/LoopSupport.xcodeproj\">\n   </FileRef>\n"

unless xml.include?('Dependencies/LoopSupport/LoopSupport.xcodeproj')
  xml = xml.sub("</Workspace>\n", "#{ref}</Workspace>\n")
  File.write(path, xml)
  puts '✅ Added LoopSupport.xcodeproj to workspace'
else
  puts 'ℹ️ LoopSupport.xcodeproj already in workspace'
end

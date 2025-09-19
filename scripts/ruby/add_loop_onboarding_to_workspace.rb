#!/usr/bin/env ruby

path = 'FreeAPS.xcworkspace/contents.xcworkspacedata'
xml = File.read(path)
ref = "   <FileRef\n      location = \"group:Dependencies/LoopOnboarding/LoopOnboarding.xcodeproj\">\n   </FileRef>\n"

unless xml.include?('Dependencies/LoopOnboarding/LoopOnboarding.xcodeproj')
  xml = xml.sub("</Workspace>\n", "#{ref}</Workspace>\n")
  File.write(path, xml)
  puts '✅ Added LoopOnboarding.xcodeproj to workspace'
else
  puts 'ℹ️ LoopOnboarding.xcodeproj already in workspace'
end



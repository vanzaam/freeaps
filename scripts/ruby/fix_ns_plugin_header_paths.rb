#!/usr/bin/env ruby

require 'xcodeproj'

proj_path = 'Dependencies/NightscoutService/NightscoutService.xcodeproj'
project = Xcodeproj::Project.open(proj_path)

plugin = project.targets.find { |t| t.name == 'NightscoutServiceKitPlugin' }
abort '❌ NightscoutServiceKitPlugin target not found' unless plugin

def normalize(value)
  case value
  when nil then []
  when String then [value]
  when Array then value
  else value.to_a
  end
end

updated = false

plugin.build_configurations.each do |cfg|
  bs = cfg.build_settings

  # Ensure HEADER_SEARCH_PATHS includes Base32 include dir from SwiftPM checkout
  headers = normalize(bs['HEADER_SEARCH_PATHS'])
  desired = [
    '$(inherited)',
    '$(BUILD_ROOT)/../SourcePackages/checkouts/Base32/Base32/include'
  ]
  desired.each do |p|
    unless headers.include?(p)
      headers << p
      updated = true
    end
  end
  bs['HEADER_SEARCH_PATHS'] = headers

  # Also add SWIFT_INCLUDE_PATHS for good measure
  swift_inc = normalize(bs['SWIFT_INCLUDE_PATHS'])
  desired_swift = '$(BUILD_ROOT)/../SourcePackages/checkouts/Base32/Base32/include'
  unless swift_inc.include?(desired_swift)
    swift_inc << desired_swift
    bs['SWIFT_INCLUDE_PATHS'] = swift_inc
    updated = true
  end
end

project.save
puts(updated ? '✅ Updated plugin header/swift include paths' : 'ℹ️ Paths already set')


#!/usr/bin/env ruby
require 'xcodeproj'

PROJECT_PATH = 'FreeAPS.xcodeproj'
KEEP_PREFIX = 'FreeAPS/Sources/Modules/'
FILENAMES = %w[
  AddCarbsLoopView.swift
  AddCarbsLoopViewModel.swift
  DashboardRootView.swift
  LoopStyleMainChartView.swift
  DashboardStateModel.swift
]

puts "🔧 Purging bad module file references..."
proj = Xcodeproj::Project.open(PROJECT_PATH)

# Collect bad refs: those with basename in FILENAMES but path not starting with KEEP_PREFIX
bad_refs = proj.files.select do |ref|
  next false unless ref.path
  name = File.basename(ref.path)
  FILENAMES.include?(name) && !ref.path.start_with?(KEEP_PREFIX)
end

bad_refs.each do |ref|
  # Remove build files referencing this ref
  proj.objects.select { |o| o.isa == 'PBXBuildFile' && o.file_ref == ref }.each do |bf|
    puts "  ❌ Removing build file: #{bf.display_name}"
    bf.remove_from_project
  end
  puts "❌ Removing bad file ref: #{ref.path}"
  ref.remove_from_project
end

proj.save
puts "✅ Done. Keep only refs with path starting '#{KEEP_PREFIX}'."

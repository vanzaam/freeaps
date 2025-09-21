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

puts "🔧 Cleaning duplicate file references..."
proj = Xcodeproj::Project.open(PROJECT_PATH)

# Build index of file refs by basename
refs_by_name = Hash.new{ |h,k| h[k] = [] }
proj.files.each do |ref|
  next unless ref.path
  name = File.basename(ref.path)
  if FILENAMES.include?(name)
    refs_by_name[name] << ref
  end
end

refs_by_name.each do |name, refs|
  # choose the ref with absolute path prefix to keep
  keep = refs.find { |r| r.path.start_with?(KEEP_PREFIX) } || refs.first
  refs.each do |ref|
    next if ref == keep
    # remove build files referencing this ref
    proj.objects.select { |o| o.isa == 'PBXBuildFile' && o.file_ref == ref }.each do |bf|
      bf.remove_from_project
    end
    puts "❌ Removing duplicate ref: #{ref.path} (keeping #{keep.path})"
    ref.remove_from_project
  end
end

proj.save
puts "✅ Done. Reopen Xcode and build."

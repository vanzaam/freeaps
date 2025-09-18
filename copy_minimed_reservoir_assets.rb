#!/usr/bin/env ruby

require 'fileutils'
require 'json'

puts "🔧 Copying Minimed reservoir assets into app asset catalog..."

src_root = 'Dependencies/MinimedKit/MinimedKitUI/Resources/MinimedKitUI.xcassets'
dst_root = 'FreeAPS/Resources/Assets.xcassets'

assets = [
  { name: 'reservoir', file: 'reservoir.pdf' },
  { name: 'reservoir_mask', file: 'reservoir_mask.pdf' }
]

assets.each do |a|
  src_pdf = File.join(src_root, "#{a[:name]}.imageset", a[:file])
  dst_set = File.join(dst_root, "#{a[:name]}.imageset")
  dst_pdf = File.join(dst_set, a[:file])
  dst_json = File.join(dst_set, 'Contents.json')

  unless File.exist?(src_pdf)
    puts "❌ Source not found: #{src_pdf}"
    next
  end

  FileUtils.mkdir_p(dst_set)
  FileUtils.cp(src_pdf, dst_pdf)

  contents = {
    images: [
      { idiom: 'universal', filename: a[:file] }
    ],
    info: { version: 1, author: 'xcode' }
  }

  File.write(dst_json, JSON.pretty_generate(contents))
  puts "✅ Copied #{a[:name]}"
end

puts '🎉 Done.'



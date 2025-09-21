#!/usr/bin/env ruby
# coding: utf-8

require 'fileutils'

ROOT = File.expand_path(File.join(__dir__, '../..'))

def update_strings_values
  base = File.join(ROOT, 'FreeAPS', 'Sources', 'Localizations', 'Main')
  locales = Dir.glob(File.join(base, '*', 'Localizable.strings'))
  changed = 0

  locales.each do |path|
    original = File.read(path, mode: 'r:bom|utf-8')
    lines = original.lines
    updated_lines = lines.map do |line|
      # Only modify right-hand value part of lines like: "key" = "value";
      if line =~ /^\s*"(.*)"\s*=\s*"(.*)";\s*$/
        key = $1
        val = $2
        # Keep keys intact (even if they include OpenAPS)
        new_val = val.gsub('OpenAPS', 'OpenAPS')
        # Also replace plain FreeAPS in values
        new_val = new_val.gsub(/\bFreeAPS\b/, 'OpenAPS')
        if new_val != val
          changed += 1
          %Q{"#{key}" = "#{new_val}";\n}
        else
          line
        end
      else
        line
      end
    end
    new_content = updated_lines.join
    next if new_content == original
    File.write(path, new_content)
    puts "✅ Updated values in #{path}"
  end
  puts "Localization value updates: #{changed} entries changed"
end

def update_markdown
  docs = Dir.glob(File.join(ROOT, '*.{md,MD,markdown,txt}'))
  changed_files = 0
  docs.each do |path|
    content = File.read(path, mode: 'r:utf-8')
    updated = content.gsub('OpenAPS', 'OpenAPS')
    next if updated == content
    File.write(path, updated)
    changed_files += 1
    puts "✅ Updated doc: #{path}"
  end
  puts "Docs updated: #{changed_files} files"
end

update_strings_values
update_markdown
puts '🎉 Done.'



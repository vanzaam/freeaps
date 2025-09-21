#!/usr/bin/env ruby
# coding: utf-8

# Rename localization KEYS across all Localizable.strings:
# - "OpenAPS"  -> "OpenAPS"
# - "FreeAPS-X"  -> "OpenAPS-X"
# - word-boundary "FreeAPS" -> "OpenAPS"
# Values are left intact (they already were updated by another script).

require 'fileutils'

ROOT = File.expand_path(File.join(__dir__, '../..'))
base = File.join(ROOT, 'FreeAPS', 'Sources', 'Localizations', 'Main')
files = Dir.glob(File.join(base, '*', 'Localizable.strings'))

def transform_key(key)
  k = key.dup
  k.gsub!('OpenAPS', 'OpenAPS')
  k.gsub!('FreeAPS-X', 'OpenAPS-X')
  k.gsub!(/\bFreeAPS\b/, 'OpenAPS')
  k
end

changed_files = []
changed_count = 0

files.each do |path|
  original = File.read(path, mode: 'r:bom|utf-8')
  out_lines = []
  modified = false

  original.each_line do |line|
    # Match lines of the form: "key" = "value";
    if line =~ /^\s*"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)";\s*$/
      key = $1
      val = $2
      new_key = transform_key(key)
      if new_key != key
        modified = true
        changed_count += 1
        out_lines << %Q{"#{new_key}" = "#{val}";\n}
      else
        out_lines << line
      end
    else
      # For comments or any other lines, keep as is but normalize comment headers
      normalized = line.gsub('OpenAPS', 'OpenAPS')
      out_lines << normalized
      modified ||= (normalized != line)
    end
  end

  next unless modified
  File.write(path, out_lines.join)
  changed_files << path
  puts "🔁 Renamed keys in: #{path}"
end

puts "Done. Files changed: #{changed_files.size}, keys changed: #{changed_count}"



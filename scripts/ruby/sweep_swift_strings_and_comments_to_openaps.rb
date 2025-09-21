#!/usr/bin/env ruby
# coding: utf-8

# Safely replace user-visible mentions of "OpenAPS" and "FreeAPS" to "OpenAPS"
# in Swift sources, but ONLY inside string literals and comments.
# - Supports // line comments, /* */ block comments (with naive nesting),
#   normal "..." strings and multiline """...""" strings.

require 'find'

ROOT = File.expand_path(File.join(__dir__, '../..'))

def replace_visible(text)
  # First replace the compound phrase, then the standalone word
  text = text.gsub('OpenAPS', 'OpenAPS')
  # Replace standalone FreeAPS word with word boundaries, case-sensitive
  text = text.gsub(/\bFreeAPS\b/, 'OpenAPS')
  text
end

def process_file(path)
  src = File.binread(path)
  out = +""
  i = 0
  n = src.bytesize
  state = :code
  block_depth = 0

  while i < n
    ch = src[i]

    if state == :code
      if src[i,3] == '"""'
        # Multiline string
        j = i + 3
        while j < n && src[j,3] != '"""'
          j += 1
        end
        j = [j, n].min
        segment = src[i, j - i + 3] rescue src[i..-1]
        # segment includes opening and closing triple quotes if found
        if segment && segment.length >= 6
          head = segment[0,3]
          body = segment[3..-4]
          tail = segment[-3,3]
          out << head << replace_visible(body) << tail
          i += segment.length
          next
        else
          out << src[i]
          i += 1
          next
        end
      elsif src[i,2] == '//'
        # Line comment to end of line
        j = i
        j += 1 while j < n && src[j] != "\n"
        segment = src[i, j - i]
        out << replace_visible(segment)
        i = j
        next
      elsif src[i,2] == '/*'
        # Block comment (naive nesting)
        j = i + 2
        depth = 1
        while j < n && depth > 0
          if src[j,2] == '/*'
            depth += 1
            j += 2
          elsif src[j,2] == '*/'
            depth -= 1
            j += 2
          else
            j += 1
          end
        end
        segment = src[i, j - i]
        out << replace_visible(segment)
        i = j
        next
      elsif src[i] == '"'
        # Normal string literal with escaping
        j = i + 1
        while j < n
          if src[j] == '\\'
            j += 2
            next
          elsif src[j] == '"'
            j += 1
            break
          else
            j += 1
          end
        end
        segment = src[i, j - i]
        # segment includes quotes
        if segment && segment.length >= 2
          head = '"'
          body = segment[1..-2]
          tail = '"'
          out << head << replace_visible(body) << tail
        else
          out << segment
        end
        i = j
        next
      else
        out << ch
        i += 1
      end
    else
      out << ch
      i += 1
    end
  end

  return nil if out == src
  File.open(path, 'wb') { |f| f.write(out) }
  path
end

changed = []

scan_dirs = [
  File.join(ROOT, 'FreeAPS'),
  File.join(ROOT, 'FreeAPSWatch WatchKit Extension')
]

scan_dirs.each do |dir|
  next unless Dir.exist?(dir)
  Find.find(dir) do |p|
    next unless p.end_with?('.swift')
    res = process_file(p)
    changed << p if res
  end
end

if changed.empty?
  puts 'No Swift files needed changes.'
else
  puts "Updated Swift files (strings/comments only): #{changed.count}"
  changed.each { |p| puts "  • #{p}" }
end

puts 'Done sweeping Swift strings/comments.'



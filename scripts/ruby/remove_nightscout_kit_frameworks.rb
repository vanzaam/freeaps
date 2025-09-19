#!/usr/bin/env ruby

require 'xcodeproj'

proj_path = 'FreeAPS.xcodeproj'
project = Xcodeproj::Project.open(proj_path)

framework_names = ['NightscoutServiceKit.framework', 'NightscoutServiceKitUI.framework']

removed = []

project.targets.each do |t|
  # Remove from Frameworks phase
  fw_phase = t.frameworks_build_phase
  fw_phase.files.dup.each do |bf|
    next unless bf.file_ref
    if framework_names.include?(bf.file_ref.path)
      fw_phase.files.delete(bf)
      removed << "#{t.name}:Frameworks:#{bf.file_ref.path}"
    end
  end

  # Remove from Embed Frameworks copy phase
  t.copy_files_build_phases.each do |phase|
    next unless phase.name == 'Embed Frameworks'
    phase.files.dup.each do |bf|
      next unless bf.file_ref
      if framework_names.include?(bf.file_ref.path)
        phase.files.delete(bf)
        removed << "#{t.name}:EmbedFrameworks:#{bf.file_ref.path}"
      end
    end
  end
end

# Remove file references
project.files.dup.each do |f|
  if framework_names.include?(f.path)
    f.remove_from_project
    removed << "fileRef:#{f.path}"
  end
end

project.save
puts "✅ Removed NightscoutServiceKit/KitUI from app project (#{removed.uniq.join(', ')})"


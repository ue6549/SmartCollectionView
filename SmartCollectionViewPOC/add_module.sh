#!/bin/bash

# Add SmartCollectionView native module to Xcode project
PROJECT_PATH="ios/SmartCollectionViewPOC.xcodeproj"
MODULE_PATH="ios/SmartCollectionView"

# Add source files to the project
echo "Adding SmartCollectionView native module to Xcode project..."

# Add the source files to the project
ruby -e "
require 'xcodeproj'

# Open the project
project = Xcodeproj::Project.open('$PROJECT_PATH')

# Find the main target
target = project.targets.find { |t| t.name == 'SmartCollectionViewPOC' }

# Add source files
source_files = [
  '$MODULE_PATH/SmartCollectionView.h',
  '$MODULE_PATH/SmartCollectionView.m',
  '$MODULE_PATH/SmartCollectionViewManager.h',
  '$MODULE_PATH/SmartCollectionViewManager.m'
]

source_files.each do |file_path|
  file_ref = project.main_group.find_subpath('SmartCollectionViewPOC', true).new_reference(File.basename(file_path))
  file_ref.path = file_path
  target.add_file_references([file_ref])
end

# Save the project
project.save
puts 'Successfully added SmartCollectionView native module to Xcode project!'
"

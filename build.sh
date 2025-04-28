#!/bin/bash

# Compile the Swift code
echo "Compiling EyeBreak..."
swiftc -o EyeBreak main.swift -framework Cocoa -framework SwiftUI

# Check if compilation was successful
if [ $? -ne 0 ]; then
    echo "Compilation failed!"
    exit 1
fi

echo "Creating app bundle..."
# Create app bundle structure
mkdir -p EyeBreak.app/Contents/MacOS
mkdir -p EyeBreak.app/Contents/Resources

# Copy files to app bundle
cp Info.plist EyeBreak.app/Contents/
cp EyeBreak EyeBreak.app/Contents/MacOS/
cp AppIcon.icns EyeBreak.app/Contents/Resources/

echo "EyeBreak executable and EyeBreak.app have been created!"
echo "To run with logs in this terminal, execute: ./EyeBreak"
echo "To run the app bundle normally (no logs here), use: open EyeBreak.app" 
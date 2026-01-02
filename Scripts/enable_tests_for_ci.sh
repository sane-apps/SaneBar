#!/bin/bash
# Enable test targets for CI builds
# This script temporarily re-enables tests in project.yml for CI environments

set -e

PROJECT_YML="project.yml"
BACKUP_YML="project.yml.ci_backup"

# Backup original project.yml
if [ ! -f "$BACKUP_YML" ]; then
    cp "$PROJECT_YML" "$BACKUP_YML"
fi

# Re-enable test targets in project.yml using Python for reliability
echo "🔧 Enabling test targets for CI..."

python3 << 'PYTHON_SCRIPT'
import re

with open('project.yml', 'r') as f:
    lines = f.readlines()

output = []
i = 0
while i < len(lines):
    line = lines[i]
    
    # Re-enable in build section
    if '# SaneVideoTests: [test]' in line:
        output.append('        SaneVideoTests: [test]\n')
        i += 1
        continue
    
    # Re-enable in test section
    if 'test:' in line and i + 1 < len(lines):
        output.append(line)
        i += 1
        # Skip comment lines and empty targets
        while i < len(lines) and ('# Temporarily' in lines[i] or 
                                   '# This is a known' in lines[i] or 
                                   '# Re-enable' in lines[i] or
                                   'targets: []' in lines[i] or
                                   '# targets:' in lines[i]):
            i += 1
        # Add actual targets
        output.append('      targets:\n')
        output.append('        - SaneVideoTests\n')
        output.append('        - SaneVideoUITests\n')
        # Skip remaining commented target lines
        while i < len(lines) and ('#   - SaneVideo' in lines[i] or lines[i].strip() == ''):
            i += 1
        continue
    
    output.append(line)
    i += 1

with open('project.yml', 'w') as f:
    f.writelines(output)

PYTHON_SCRIPT

echo "✅ Test targets enabled. Regenerating Xcode project..."
xcodegen generate

echo "✅ Ready for CI test execution"

#!/bin/bash
# Post-processing script for Mockolo-generated mocks
# Adds @testable import SaneVideo if not present

MOCKS_FILE="SaneVideoTests/Mocks/Mocks.swift"

if [ -f "$MOCKS_FILE" ]; then
    # Check if @testable import already exists
    if ! grep -q "@testable import SaneVideo" "$MOCKS_FILE"; then
        # Find the last import line and add @testable import after it
        sed -i '' '/^import /a\
@testable import SaneVideo
' "$MOCKS_FILE"
        echo "✅ Added @testable import SaneVideo to mocks"
    fi
fi


#!/bin/bash
# Post-processing script for Mockolo-generated mocks
# Adds @testable import SaneBar if not present

MOCKS_FILE="SaneBarTests/Mocks/Mocks.swift"

if [ -f "$MOCKS_FILE" ]; then
    # Check if @testable import already exists
    if ! grep -q "@testable import SaneBar" "$MOCKS_FILE"; then
        # Find the last import line and add @testable import after it
        sed -i '' '/^import /a\
@testable import SaneBar
' "$MOCKS_FILE"
        echo "✅ Added @testable import SaneBar to mocks"
    fi
fi


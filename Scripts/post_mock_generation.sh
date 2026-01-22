#!/bin/bash

# Get project name from current directory
PROJECT_NAME=$(basename "$PWD")

# Adds @testable import PROJECT_NAME if not present
# to generated mocks file
MOCKS_FILE="${PROJECT_NAME}Tests/Mocks/Mocks.swift"

if [ -f "$MOCKS_FILE" ]; then
    if ! grep -q "@testable import $PROJECT_NAME" "$MOCKS_FILE"; then
        # Insert import after the last import statement
        sed -i '' "/^import /a\\
@testable import $PROJECT_NAME
" "$MOCKS_FILE"
        echo "✅ Added @testable import $PROJECT_NAME to mocks"
    else
        echo "ℹ️  @testable import already present"
    fi
else
    echo "⚠️  Mocks file not found at $MOCKS_FILE"
fi


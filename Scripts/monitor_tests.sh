#!/bin/bash
# Monitor test execution with live logs and timeout detection

SCHEME="${1:-SaneBar}"
TEST_NAME="${2:-}"
TIMEOUT="${3:-300}" # 5 minutes default

echo "🔍 Monitoring tests for scheme: $SCHEME"
if [ -n "$TEST_NAME" ]; then
    echo "   Test: $TEST_NAME"
fi
echo "   Timeout: ${TIMEOUT}s"
echo ""

# Start test in background
TEST_PID=""
if [ -n "$TEST_NAME" ]; then
    xcodebuild test -scheme "$SCHEME" -destination 'platform=macOS,arch=arm64' -only-testing:"$TEST_NAME" > /tmp/test_output.log 2>&1 &
else
    xcodebuild test -scheme "$SCHEME" -destination 'platform=macOS,arch=arm64' > /tmp/test_output.log 2>&1 &
fi
TEST_PID=$!

# Monitor with timeout
START_TIME=$(date +%s)
TIMEOUT_REACHED=false

while kill -0 $TEST_PID 2>/dev/null; do
    ELAPSED=$(($(date +%s) - START_TIME))
    
    # Check for timeout
    if [ $ELAPSED -gt $TIMEOUT ]; then
        echo "⏱️  TIMEOUT: Test exceeded ${TIMEOUT}s, killing process..."
        kill -9 $TEST_PID 2>/dev/null
        TIMEOUT_REACHED=true
        break
    fi
    
    # Show progress every 10 seconds
    if [ $((ELAPSED % 10)) -eq 0 ]; then
        echo "⏱️  Elapsed: ${ELAPSED}s / ${TIMEOUT}s"
        # Show last few lines of output
        tail -3 /tmp/test_output.log 2>/dev/null | sed 's/^/   /'
    fi
    
    sleep 1
done

# Wait for process to finish
wait $TEST_PID 2>/dev/null
EXIT_CODE=$?

# Show final results
echo ""
echo "📊 Test Results:"
if [ "$TIMEOUT_REACHED" = true ]; then
    echo "❌ Test timed out after ${TIMEOUT}s"
    exit 124
elif [ $EXIT_CODE -eq 0 ]; then
    echo "✅ Tests passed"
    grep -E "(Test Case|PASSED)" /tmp/test_output.log | tail -20
else
    echo "❌ Tests failed (exit code: $EXIT_CODE)"
    grep -E "(Test Case|FAILED|error:)" /tmp/test_output.log | tail -30
fi

exit $EXIT_CODE


#!/bin/bash

# Configuration
PROJECT_DIR="/Users/sj/SaneBar"
LOG_FILE="$PROJECT_DIR/website_publish.log"
MAX_RETRIES=3
RETRY_DELAY=60 # seconds

# Setup logging
exec 1>>"$LOG_FILE"
exec 2>&1

echo "--- Starting Website Publication: $(date) ---"

# Navigate to project
cd "$PROJECT_DIR" || {
    echo "Error: Could not find project directory."
    osascript -e 'display notification "Could not find SaneBar directory" with title "SaneBar Publisher" subtitle "Publication Failed"'
    exit 1
}

# 1. Apply the Changes
if [ -f "docs/index_preview.html" ]; then
    echo "Applying index_preview.html to index.html..."
    mv docs/index_preview.html docs/index.html
else
    echo "Error: Preview file not found!"
    osascript -e 'display notification "Preview file missing" with title "SaneBar Publisher" subtitle "Publication Failed"'
    exit 1
fi

# 2. Git Operations with Retry Logic
echo "Staging and committing..."
git add docs/index.html
git commit -m "feat(web): update landing page visuals, SEO, and icons [Auto-Published]"

attempt=1
success=false

while [ $attempt -le $MAX_RETRIES ]; do
    echo "Push attempt $attempt of $MAX_RETRIES..."
    if git push origin main; then
        success=true
        break
    else
        echo "Push failed. Retrying in $RETRY_DELAY seconds..."
        sleep $RETRY_DELAY
        ((attempt++))
    fi
done

# 3. Final Notification
if [ "$success" = true ]; then
    echo "Publication successful!"
    osascript -e 'display notification "Website successfully updated and pushed to GitHub." with title "SaneBar Publisher" subtitle "Publication Complete"'
    
    # Cleanup self (optional, but good for one-off tasks)
    # launchctl unload ~/Library/LaunchAgents/com.sanebar.website.publisher.plist
else
    echo "Publication failed after $MAX_RETRIES attempts."
    osascript -e 'display notification "Git push failed after multiple retries. Check logs." with title "SaneBar Publisher" subtitle "Publication Failed"'
    exit 1
fi

echo "--- Finished: $(date) ---"
exit 0

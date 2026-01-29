#!/bin/bash
#
# Zoom Meeting Auto-Watcher
# Automatically starts/stops recording when Zoom meetings begin/end
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RECORDER="$SCRIPT_DIR/record-meeting.sh"
CHECK_INTERVAL=5  # seconds

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Send macOS notification
notify() {
    local title="$1"
    local message="$2"
    osascript -e "display notification \"$message\" with title \"$title\""
}

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}👁️  Zoom Meeting Watcher${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Monitoring for Zoom meetings..."
echo "Press Ctrl+C to stop watching"
echo ""

notify "Meeting Recorder" "Watcher is now active"

was_in_meeting=false

is_in_meeting() {
    # Method 1: Check for CptHost (Zoom's meeting process)
    if pgrep -f "CptHost" > /dev/null 2>&1; then
        return 0
    fi

    # Method 2: Check for zoom meeting audio process
    if pgrep -f "zoom.*Meeting" > /dev/null 2>&1; then
        return 0
    fi

    # Method 3: Check Zoom window names (may need accessibility permissions)
    local zoom_windows=$(osascript -e 'tell application "System Events"
        if exists (process "zoom.us") then
            tell process "zoom.us"
                try
                    set windowNames to name of every window
                    return windowNames as string
                on error
                    return ""
                end try
            end tell
        else
            return ""
        end if
    end tell' 2>/dev/null)

    if [[ "$zoom_windows" == *"Zoom Meeting"* ]] || \
       [[ "$zoom_windows" == *"meeting"* ]] || \
       [[ "$zoom_windows" == *"Webinar"* ]]; then
        return 0
    fi

    return 1
}

while true; do
    if is_in_meeting; then
        if [[ "$was_in_meeting" == false ]]; then
            echo -e "${GREEN}[$(date +%H:%M:%S)] Meeting detected! Starting recording...${NC}"
            notify "🔴 Recording Started" "Your meeting is being recorded"
            "$RECORDER" start &
            was_in_meeting=true
        fi
    else
        if [[ "$was_in_meeting" == true ]]; then
            echo -e "${YELLOW}[$(date +%H:%M:%S)] Meeting ended. Stopping recording...${NC}"
            notify "⏹️ Recording Stopped" "Transcribing your meeting..."
            "$RECORDER" stop
            notify "✅ Transcription Complete" "Check your meeting folder"
            was_in_meeting=false
            echo ""
            echo "Waiting for next meeting..."
        fi
    fi
    sleep $CHECK_INTERVAL
done

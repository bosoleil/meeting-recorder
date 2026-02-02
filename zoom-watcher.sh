#!/bin/bash
#
# Zoom Meeting Auto-Watcher
# Automatically starts/stops recording when Zoom meetings begin/end
#

# Ensure PATH includes Homebrew and Miniconda (for LaunchAgent compatibility)
export PATH="/opt/homebrew/bin:/Users/bombin/miniconda3/bin:$PATH"

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
not_in_meeting_count=0
GRACE_PERIOD=6  # Require 6 consecutive "not in meeting" checks (30 seconds) before stopping

is_in_meeting() {
    # First check: Zoom must be running
    if ! pgrep -x "zoom.us" > /dev/null 2>&1; then
        return 1
    fi

    # Method 1: Check for CptHost (Zoom's meeting process)
    if pgrep -f "CptHost" > /dev/null 2>&1; then
        return 0
    fi

    # Method 2: Check for zoom audio/video processes
    if pgrep -f "zoom.*caphost" > /dev/null 2>&1; then
        return 0
    fi

    # Method 3: Check Zoom window names for meeting indicators
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
       [[ "$zoom_windows" == *"Webinar"* ]] || \
       [[ "$zoom_windows" == *"Meeting"* ]]; then
        return 0
    fi

    # Method 4: Check if Zoom has more than 3 windows (likely in a meeting)
    local window_count=$(osascript -e 'tell application "System Events" to count windows of process "zoom.us"' 2>/dev/null)
    if [[ "$window_count" -gt 3 ]]; then
        return 0
    fi

    return 1
}

while true; do
    if is_in_meeting; then
        not_in_meeting_count=0  # Reset counter when in meeting
        if [[ "$was_in_meeting" == false ]]; then
            echo -e "${GREEN}[$(date +%H:%M:%S)] Meeting detected! Starting recording...${NC}"
            notify "🔴 Recording Started" "Your meeting is being recorded"
            "$RECORDER" start &
            was_in_meeting=true
        fi
    else
        if [[ "$was_in_meeting" == true ]]; then
            not_in_meeting_count=$((not_in_meeting_count + 1))
            echo -e "${YELLOW}[$(date +%H:%M:%S)] Meeting check: not detected ($not_in_meeting_count/$GRACE_PERIOD)${NC}"

            if [[ $not_in_meeting_count -ge $GRACE_PERIOD ]]; then
                echo -e "${YELLOW}[$(date +%H:%M:%S)] Meeting ended. Stopping recording...${NC}"
                notify "⏹️ Recording Stopped" "Transcribing your meeting..."
                "$RECORDER" stop
                notify "✅ Transcription Complete" "Check your meeting folder"
                was_in_meeting=false
                not_in_meeting_count=0
                echo ""
                echo "Waiting for next meeting..."
            fi
        fi
    fi
    sleep $CHECK_INTERVAL
done

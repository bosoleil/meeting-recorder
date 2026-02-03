#!/bin/bash
#
# Local Meeting Recorder & Transcriber
# Records your microphone audio during meetings and transcribes locally with Whisper
#

# Ensure PATH includes Homebrew and Miniconda (for LaunchAgent compatibility)
export PATH="/opt/homebrew/bin:/Users/bombin/miniconda3/bin:$PATH"

# Configuration
BASE_DIR="/Users/bombin/Local Records/meeting"
WHISPER_MODEL="mlx-community/whisper-large-v3-turbo"  # Fast & accurate on Apple Silicon
LANGUAGE="en"         # Change if you speak another language

# Auto-detect audio devices
get_audio_devices() {
    local devices=$(ffmpeg -f avfoundation -list_devices true -i "" 2>&1)

    # Find BlackHole for system audio capture
    BLACKHOLE_DEVICE=""
    if echo "$devices" | grep -q "BlackHole"; then
        BLACKHOLE_DEVICE=$(echo "$devices" | grep "BlackHole" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/')
    fi

    # Find MacBook Pro Microphone for user's voice
    MIC_DEVICE=""
    if echo "$devices" | grep -q "MacBook Pro Microphone"; then
        MIC_DEVICE=$(echo "$devices" | grep "MacBook Pro Microphone" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/')
    fi

    # Fallback to any mic if MacBook Pro Mic not found
    if [[ -z "$MIC_DEVICE" ]]; then
        MIC_DEVICE=$(echo "$devices" | grep -i "microphone" | head -1 | sed 's/.*\[\([0-9]*\)\].*/\1/')
    fi
}

get_audio_devices

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get current date
DATE=$(date +"%Y-%m-%d")
TIMESTAMP=$(date +"%H-%M-%S")

# Try to get Zoom meeting name
get_zoom_meeting_name() {
    local meeting_name=""

    # Method 1: Get all Zoom window titles and find the meeting one
    local zoom_windows=$(osascript -e 'tell application "System Events"
        if exists (process "zoom.us") then
            tell process "zoom.us"
                try
                    set windowList to name of every window
                    set AppleScript'\''s text item delimiters to "|||"
                    return windowList as text
                on error
                    return ""
                end try
            end tell
        else
            return ""
        end if
    end tell' 2>/dev/null)

    # Parse window titles - look for actual meeting name (not generic titles)
    IFS='|||' read -ra WINDOWS <<< "$zoom_windows"
    for window in "${WINDOWS[@]}"; do
        # Skip generic Zoom windows
        if [[ "$window" != "Zoom" ]] && \
           [[ "$window" != "Zoom Meeting" ]] && \
           [[ "$window" != "zoom.us" ]] && \
           [[ "$window" != "Zoom Workplace" ]] && \
           [[ "$window" != "zoom floating video window" ]] && \
           [[ "$window" != "" ]] && \
           [[ ! "$window" =~ ^[0-9]+$ ]]; then
            meeting_name="$window"
            break
        fi
    done

    # Method 2: Check Calendar for current meeting (with 3 second timeout)
    if [[ -z "$meeting_name" ]]; then
        meeting_name=$(timeout 3 osascript -e '
            tell application "Calendar"
                set currentDate to current date
                set todayEvents to {}
                repeat with cal in calendars
                    try
                        set todayEvents to todayEvents & (every event of cal whose start date ≤ currentDate and end date ≥ currentDate)
                    end try
                end repeat
                if (count of todayEvents) > 0 then
                    return summary of item 1 of todayEvents
                end if
            end tell
            return ""
        ' 2>/dev/null)
    fi

    # Method 3: Try to get from Zoom's recent meetings database
    if [[ -z "$meeting_name" ]]; then
        local zoom_db="$HOME/Library/Application Support/zoom.us/data/zoomus.db"
        if [[ -f "$zoom_db" ]]; then
            meeting_name=$(sqlite3 "$zoom_db" "SELECT topic FROM zoom_meeting_history ORDER BY start_time DESC LIMIT 1" 2>/dev/null)
        fi
    fi

    # Fallback to timestamp if no name found
    if [[ -z "$meeting_name" ]] || [[ "$meeting_name" == "Zoom Meeting" ]]; then
        echo "meeting-${TIMESTAMP}"
    else
        # Sanitize for filename (keep more readable)
        echo "$meeting_name" | sed 's/[^a-zA-Z0-9 _-]//g' | tr ' ' '-' | tr '[:upper:]' '[:lower:]' | head -c 60
    fi
}

# Check if Zoom is running
check_zoom() {
    pgrep -x "zoom.us" > /dev/null 2>&1
    return $?
}

# Recording file paths
MEETING_NAME=""
RECORDING_DIR=""
AUDIO_FILE=""
PID_FILE="/tmp/meeting-recorder.pid"

start_recording() {
    if [[ -f "$PID_FILE" ]]; then
        echo -e "${RED}Recording already in progress!${NC}"
        echo "Use: $0 stop"
        exit 1
    fi

    # Get meeting name
    if check_zoom; then
        MEETING_NAME=$(get_zoom_meeting_name)
        echo -e "${GREEN}✓ Zoom detected${NC}"
    else
        echo -e "${YELLOW}⚠ Zoom not detected, recording anyway...${NC}"
        MEETING_NAME="meeting-${TIMESTAMP}"
    fi

    # Create directory structure
    RECORDING_DIR="${BASE_DIR}/${DATE}/${MEETING_NAME}"
    mkdir -p "$RECORDING_DIR"

    AUDIO_FILE="${RECORDING_DIR}/audio.wav"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🎙️  Starting Recording${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Meeting: ${YELLOW}${MEETING_NAME}${NC}"
    echo -e "Date: ${DATE}"

    # Start recording in background
    # Boost BlackHole by 20dB to compensate for low system volume
    if [[ -n "$BLACKHOLE_DEVICE" ]] && [[ -n "$MIC_DEVICE" ]]; then
        # Record BOTH system audio (BlackHole) AND microphone, mix them together
        echo -e "Audio: ${GREEN}BlackHole + Microphone (full meeting capture)${NC}"
        echo -e "Saving to: ${RECORDING_DIR}"
        echo ""
        echo -e "${YELLOW}Press Ctrl+C or run '$0 stop' to stop recording${NC}"
        echo ""
        ffmpeg -f avfoundation -i ":${BLACKHOLE_DEVICE}" -f avfoundation -i ":${MIC_DEVICE}" \
            -filter_complex "[0:a]volume=20dB[a0];[1:a]volume=10dB[a1];[a0][a1]amix=inputs=2:duration=longest[aout]" -map "[aout]" \
            -acodec pcm_s16le -ar 48000 -ac 2 "$AUDIO_FILE" -y -loglevel quiet &
    elif [[ -n "$BLACKHOLE_DEVICE" ]]; then
        # BlackHole only (system audio) - boost by 20dB
        echo -e "Audio: ${YELLOW}BlackHole only (no mic)${NC}"
        echo -e "Saving to: ${RECORDING_DIR}"
        echo ""
        echo -e "${YELLOW}Press Ctrl+C or run '$0 stop' to stop recording${NC}"
        echo ""
        ffmpeg -f avfoundation -i ":${BLACKHOLE_DEVICE}" -af "volume=20dB" -acodec pcm_s16le -ar 48000 -ac 2 "$AUDIO_FILE" -y -loglevel quiet &
    else
        # Microphone only (fallback)
        echo -e "Audio: ${YELLOW}Microphone only (no BlackHole)${NC}"
        echo -e "Saving to: ${RECORDING_DIR}"
        echo ""
        echo -e "${YELLOW}Press Ctrl+C or run '$0 stop' to stop recording${NC}"
        echo ""
        ffmpeg -f avfoundation -i ":${MIC_DEVICE:-2}" -acodec pcm_s16le -ar 16000 -ac 1 "$AUDIO_FILE" -y -loglevel quiet &
    fi
    FFMPEG_PID=$!

    # Save state
    echo "$FFMPEG_PID" > "$PID_FILE"
    echo "$AUDIO_FILE" > "/tmp/meeting-recorder-file.txt"
    echo "$RECORDING_DIR" > "/tmp/meeting-recorder-dir.txt"

    echo -e "${GREEN}Recording started (PID: $FFMPEG_PID)${NC}"

    # If running interactively, wait for Ctrl+C
    if [[ -t 0 ]]; then
        trap "stop_recording; exit 0" INT TERM
        while kill -0 $FFMPEG_PID 2>/dev/null; do
            sleep 1
        done
    fi
}

stop_recording() {
    if [[ ! -f "$PID_FILE" ]]; then
        echo -e "${RED}No recording in progress${NC}"
        exit 1
    fi

    FFMPEG_PID=$(cat "$PID_FILE")
    AUDIO_FILE=$(cat "/tmp/meeting-recorder-file.txt" 2>/dev/null)
    RECORDING_DIR=$(cat "/tmp/meeting-recorder-dir.txt" 2>/dev/null)

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}🛑 Stopping Recording${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Stop ffmpeg gracefully
    kill -INT $FFMPEG_PID 2>/dev/null
    sleep 2
    kill -9 $FFMPEG_PID 2>/dev/null

    # Cleanup PID file
    rm -f "$PID_FILE" "/tmp/meeting-recorder-file.txt" "/tmp/meeting-recorder-dir.txt"

    if [[ -f "$AUDIO_FILE" ]]; then
        DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$AUDIO_FILE" 2>/dev/null | cut -d. -f1)
        echo -e "Recording saved: ${GREEN}${AUDIO_FILE}${NC}"
        echo -e "Duration: ${DURATION:-0} seconds"
        echo ""

        # Start transcription
        transcribe_audio "$AUDIO_FILE" "$RECORDING_DIR"
    else
        echo -e "${RED}No audio file found${NC}"
    fi
}

transcribe_audio() {
    local audio="$1"
    local output_dir="$2"
    local normalized_audio="$output_dir/audio_normalized.wav"

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📝 Preparing audio for transcription...${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Check audio volume level
    local mean_vol=$(ffmpeg -i "$audio" -af "volumedetect" -f null /dev/null 2>&1 | grep "mean_volume" | awk '{print $5}')
    echo -e "Audio mean volume: ${mean_vol} dB"

    # Warn if audio is too quiet (likely microphone not capturing speakers well)
    local vol_num=${mean_vol%.*}
    if [[ "$vol_num" -lt -25 ]]; then
        echo -e "${RED}⚠ Audio is very quiet (${mean_vol} dB). Transcription may be poor.${NC}"
        echo -e "${YELLOW}Tip: Set up BlackHole for system audio capture - see README${NC}"
    fi

    # Normalize audio for better transcription
    echo -e "${YELLOW}Normalizing audio...${NC}"
    ffmpeg -y -i "$audio" -af "loudnorm=I=-16:TP=-1.5:LRA=11" -ar 16000 -ac 1 "$normalized_audio" -loglevel quiet

    if [[ ! -f "$normalized_audio" ]]; then
        echo -e "${YELLOW}Normalization failed, using original audio${NC}"
        normalized_audio="$audio"
    fi

    echo -e "${GREEN}📝 Transcribing with MLX Whisper (GPU accelerated)...${NC}"
    echo -e "${YELLOW}This should only take a few minutes...${NC}"
    echo ""

    mlx_whisper "$normalized_audio" \
        --model "$WHISPER_MODEL" \
        --language "$LANGUAGE" \
        --output-dir "$output_dir" \
        --output-format all \
        --verbose False \
        --condition-on-previous-text False \
        --no-speech-threshold 0.6

    # Rename normalized output to match expected filename
    if [[ -f "$output_dir/audio_normalized.txt" ]]; then
        mv "$output_dir/audio_normalized.txt" "$output_dir/audio.txt"
        mv "$output_dir/audio_normalized.srt" "$output_dir/audio.srt" 2>/dev/null
        mv "$output_dir/audio_normalized.vtt" "$output_dir/audio.vtt" 2>/dev/null
        mv "$output_dir/audio_normalized.json" "$output_dir/audio.json" 2>/dev/null
        mv "$output_dir/audio_normalized.tsv" "$output_dir/audio.tsv" 2>/dev/null
        rm -f "$normalized_audio"  # Clean up normalized audio
    fi

    if [[ $? -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}✓ Transcription complete!${NC}"
        echo -e "Files saved in: ${YELLOW}${output_dir}${NC}"
        echo ""
        echo "Generated files:"
        ls -la "$output_dir"/*.txt "$output_dir"/*.srt "$output_dir"/*.vtt 2>/dev/null | awk '{print "  " $NF}'

        # Show preview of transcript
        if [[ -f "$output_dir/audio.txt" ]]; then
            echo ""
            echo -e "${BLUE}━━━ Transcript Preview ━━━${NC}"
            head -20 "$output_dir/audio.txt"
            echo "..."
        fi
    else
        echo -e "${RED}Transcription failed${NC}"
    fi
}

# Show status
status() {
    if [[ -f "$PID_FILE" ]]; then
        FFMPEG_PID=$(cat "$PID_FILE")
        AUDIO_FILE=$(cat "/tmp/meeting-recorder-file.txt" 2>/dev/null)
        if kill -0 $FFMPEG_PID 2>/dev/null; then
            echo -e "${GREEN}🔴 Recording in progress${NC}"
            echo "PID: $FFMPEG_PID"
            echo "File: $AUDIO_FILE"
        else
            echo -e "${YELLOW}Stale PID file found, cleaning up...${NC}"
            rm -f "$PID_FILE" "/tmp/meeting-recorder-file.txt" "/tmp/meeting-recorder-dir.txt"
        fi
    else
        echo -e "${BLUE}No recording in progress${NC}"
    fi

    if check_zoom; then
        echo -e "${GREEN}✓ Zoom is running${NC}"
    else
        echo -e "${YELLOW}○ Zoom is not running${NC}"
    fi

    # Show audio devices
    if [[ -n "$BLACKHOLE_DEVICE" ]] && [[ -n "$MIC_DEVICE" ]]; then
        echo -e "${GREEN}✓ Audio: BlackHole + Microphone (full capture)${NC}"
    elif [[ -n "$BLACKHOLE_DEVICE" ]]; then
        echo -e "${YELLOW}○ Audio: BlackHole only (no mic - won't capture your voice)${NC}"
    else
        echo -e "${YELLOW}○ Audio: Microphone only (set up BlackHole for system audio)${NC}"
    fi
}

# Transcribe existing file
transcribe_only() {
    local file="$1"
    if [[ -z "$file" ]]; then
        echo "Usage: $0 transcribe <audio_file>"
        exit 1
    fi

    if [[ ! -f "$file" ]]; then
        echo -e "${RED}File not found: $file${NC}"
        exit 1
    fi

    local dir=$(dirname "$file")
    transcribe_audio "$file" "$dir"
}

# Usage
usage() {
    echo "Local Meeting Recorder & Transcriber"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  start       Start recording (auto-detects Zoom meeting name)"
    echo "  stop        Stop recording and transcribe"
    echo "  status      Check recording status"
    echo "  transcribe  Transcribe an existing audio file"
    echo ""
    echo "Examples:"
    echo "  $0 start              # Start recording"
    echo "  $0 stop               # Stop and transcribe"
    echo "  $0 transcribe file.wav # Transcribe existing file"
    echo ""
    echo "Configuration (edit script to change):"
    echo "  Model: $WHISPER_MODEL"
    echo "  Audio device: $AUDIO_DEVICE"
    echo "  Language: $LANGUAGE"
    echo "  Output dir: $BASE_DIR"
}

# Main
case "${1:-}" in
    start)
        start_recording
        ;;
    stop)
        stop_recording
        ;;
    status)
        status
        ;;
    transcribe)
        transcribe_only "$2"
        ;;
    *)
        usage
        ;;
esac

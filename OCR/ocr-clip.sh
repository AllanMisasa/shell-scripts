#!/bin/bash

# Temporary file paths
TEMP_IMAGE="/tmp/ocr_capture.png"
TEMP_TEXT="/tmp/ocr_result.txt"

# Check which DE or compositor is used
detect_session_type() {
    if [ "$XDG_SESSION_TYPE" == "wayland" ]; then
        echo "Wayland"
    elif [ "$XDG_SESSION_TYPE" == "x11" ]; then
        echo "X11"
    else
        echo "Unknown"
    fi
}

detect_hyprland() {
    if pgrep -x "Hyprland" > /dev/null; then
        echo "Hyprland"
    else
        echo "Not Hyprland"
    fi
}

# Function to detect the desktop environment (GNOME, etc.)
detect_desktop_environment() {
    if [[ "$XDG_CURRENT_DESKTOP" =~ .*GNOME.* ]]; then
        echo "GNOME"
    elif [[ "$XDG_CURRENT_DESKTOP" =~ .*Hyprland.* ]]; then
        echo "Hyprland"
    elif [[ "$XDG_CURRENT_DESKTOP" =~ .*sway.* ]]; then
        echo "sway"
    else
        echo "Other"
    fi
}

# Main logic: Check session type and desktop environment
session_type=$(detect_session_type)
desktop_env=$(detect_desktop_environment)
hyprland_status=$(detect_hyprland)

echo "Session Type: $session_type"
echo "Desktop Environment: $desktop_env"
echo "Hyprland Status: $hyprland_status"

if [ "$hyprland_status" == "Hyprland" ]; then
    hyprctl -j activewindow | jq -r '"\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | grim -g - "$TEMP_IMAGE"
elif [ "$session_type" == "Wayland" ] && [ "$desktop_env" == "GNOME" ]; then
    gnome-screenshot -a -f "$TEMP_IMAGE"
elif [ "$desktop_env" == "sway" ]; then
    exec grim -g "$(slurp)" - | tesseract stdin stdout | wl-copy
elif [ "$session_type" == "x11" ]; then
    scrot -s "$TEMP_IMAGE" 
else
    echo "Session and/or environment not supported"
fi

# Check if the screenshot was successfully captured
if [ ! -f "$TEMP_IMAGE" ]; then
    echo "Screenshot was not captured. Exiting."
    exit 1
fi

# Perform OCR on the captured image
tesseract "$TEMP_IMAGE" "$TEMP_TEXT" --psm 6 -l eng

# Check if the OCR output contains text
if [ ! -s "${TEMP_TEXT}.txt" ]; then
    echo "No text detected in the selected area."
else
    # Output the OCR result to the terminal
    echo "OCR Result:"
    cat "${TEMP_TEXT}.txt"

    # Copy the OCR result to the clipboard
    cat "${TEMP_TEXT}.txt" | xclip -selection clipboard
    echo "Text copied to clipboard."
fi

# Clean up temporary files
rm "$TEMP_IMAGE" "${TEMP_TEXT}.txt"

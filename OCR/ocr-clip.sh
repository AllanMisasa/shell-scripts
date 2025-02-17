#!/bin/bash

# Temporary file paths
TEMP_IMAGE="/tmp/ocr_capture.png"
TEMP_TEXT="/tmp/ocr_result.txt"

# Capture a rectangular area of the screen using Gnome Screenshot
gnome-screenshot -a -f "$TEMP_IMAGE"

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

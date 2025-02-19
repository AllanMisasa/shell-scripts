#!/bin/bash

for file in *.mkv *.mp4; do
    # Check if the file exists to avoid errors
    if [[ -f "$file" ]]; then
        # Extract the filename without its extension
        filename="${file%.*}"
        echo "Processing $file..."
        
        # Encode the file to HEVC format using ffmpeg
        sudo ffmpeg -i "$file" -c:v hevc_nvenc -vtag hvc1 "${filename}.mp4"
        
        echo "Finished encoding $file to ${filename}.mp4"
    fi
done

echo "All files have been processed."

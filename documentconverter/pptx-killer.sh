#!/bin/bash

# Required:
#   pptx2md - pip install pptx2md https://github.com/ssine/pptx2md
#   marp-cli - https://github.com/marp-team/marp-cli/releases
#   pandoc - 

for file in *; do
  ext="${file##*.}"
    if [[ $ext == pptx ]]; then
      pptx2md "${file}" -o "${file%.*}".md -i images --enable-slides
      marp "${file%.*}.md" -o "${file%.*}.html" --allow-local-files
    elif [[ $ext == docx ]]; then
      pandoc -f docx -t gfm --wrap=none --extract-media=images -s "${file%.*}.docx" -o "${file%.*}.md"
    fi
  echo "Conversion done."
done

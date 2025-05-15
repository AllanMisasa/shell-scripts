#!/bin/bash

for file in *; do
  ext="${file##*.}"
    echo $ext
    if [[ $ext == pptx ]]; then
      pptx2md "${file}" -o "${file%.*}".md -i images --enable-slides
      marp "${file%.*}.md" -o "${file%.*}.html" --allow-local-files
    elif [[ $ext == docx ]]; then
      pandoc -f docx -t markdown "${file%.*}.docx" -o "${file%.*}.md"
      #marp "${file%.*}.md" -o "${file%.*}.html" --allow-local-files
    fi
done

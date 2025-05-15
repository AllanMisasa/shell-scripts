#!/bin/bash

for file in *; do
  ext="${file##*.}"
    echo $ext
    if [[ $ext == pptx ]]; then
      pptx2md "${file}" -o "${file%.*}".md -i images --enable-slides
    #elif [[ $ext == docx ]]; then
    #    
      marp "${file%.*}.md" -o "${file%.*}.html" --allow-local-files 
    fi
done

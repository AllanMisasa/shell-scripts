file="$1"
convertBool="$2"

if [ convertBool ]; then 
  pandoc -i "$file" -o "output.md"
  cat "output.md" | wl-copy
else
  cat "$file" | wl-copy
fi 

file="$1"
convertBool="$2"

if [ convertBool = "convert" ]; then 
  pandoc -i "$file" -o "output.md"
  cat "output.md" | wl-copy
else
  cat "$file" | wl-copy
fi 

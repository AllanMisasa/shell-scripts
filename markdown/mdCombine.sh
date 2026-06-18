
for f in *.md; do cat "$f"; echo "\newline"; done > out && mv out output.md

#!/usr/bin/env bash
#
# splitFlacCue.sh - find FLAC/CUE album images and split them into tracks.
#
# For every *.cue file found under the given directories, this script locates
# the FLAC image referenced by the cue sheet (or a same-named .flac next to
# it) and runs shnsplit to write one file per track.
#
# Dependencies: bash, find, awk, sort, shnsplit (shntool), metaflac (flac).
# Optional:     cuetag + cueprint (cuetools) to write FLAC tags.

set -euo pipefail

template='%n - %t'
format='flac'
outbase=''
dry_run=0
force=0
noncd=0
tag=1

tag_warned=0
candidates=0
albums_ok=0
skipped_albums=0
failed_albums=0
tracks_written=0
tmp=''

cleanup() {
  if [[ -n $tmp && -d $tmp ]]; then
    rm -rf -- "$tmp"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  cat <<'EOF'
Usage: splitFlacCue.sh [OPTIONS] [DIR...]

Search DIR (default: current directory) recursively for CUE sheets that have
a corresponding FLAC image, then split each image into one file per track
with shnsplit.

Options:
  -n, --dry-run          Show what would be done, do not split anything
  -f, --force            Overwrite existing track files
  -d, --output-dir DIR   Write each album into DIR/<cue-name>/ instead of
                         next to the CUE sheet
  -t, --template FMT     shnsplit output name template (default: "%n - %t")
                         Tokens: %n number, %t title, %p performer, %a album
  -o, --format FMT       shnsplit output format (default: flac)
                         Example: -o "flac flac -8"
      --noncd            Split even if the image is not CD quality
                         (44100 Hz, 2 channels, 16 bit). shnsplit treats CUE
                         split points as CD time, so other formats are cut at
                         the wrong offsets.
      --no-tag           Do not tag the output, even if cuetag is installed
  -h, --help             Show this help and exit

Examples:
  splitFlacCue.sh ~/Music
  splitFlacCue.sh --dry-run ~/Music
  splitFlacCue.sh -d ~/Music/split ~/Music/Albums
  splitFlacCue.sh --force --template "%n. %t" ~/Music/Albums

Notes:
  * A CUE sheet referencing more than one FLAC file is skipped; such rips are
    usually already track-per-file.
  * Existing output files are skipped unless --force is given.
  * Multi-disc sets work as long as each disc has its own CUE and FLAC image.
EOF
}

warn()  { printf 'warning: %s\n' "$*" >&2; }
error() { printf 'error: %s\n' "$*" >&2; }
info()  { printf '%s\n' "$*"; }
die()   { error "$*"; exit 1; }

require_deps() {
  local -a missing=()
  local cmd
  for cmd in find awk sort mktemp shnsplit metaflac; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if ((${#missing[@]})); then
    error "missing required command(s): ${missing[*]}"
    error "install shntool (for shnsplit) and flac (for metaflac)"
    exit 1
  fi
}

# Print the FILE entries of a CUE sheet, one per line.
extract_file_refs() {
  awk '
    {
      line = $0
      low = tolower(line)
    }
    low ~ /^[[:space:]]*file[[:space:]]+"/ {
      i = index(line, "\"")
      rest = substr(line, i + 1)
      j = index(rest, "\"")
      if (j > 1) print substr(rest, 1, j - 1)
      next
    }
    low ~ /^[[:space:]]*file[[:space:]]+[^"]/ {
      sub(/^[[:space:]]*[Ff][Ii][Ll][Ee][[:space:]]+/, "", line)
      sub(/[[:space:]].*$/, "", line)
      if (line != "") print line
    }
  ' "$1"
}

count_tracks() {
  awk '
    tolower($0) ~ /^[[:space:]]*track[[:space:]]+[0-9]+[[:space:]]+audio/ { n++ }
    END { print n + 0 }
  ' "$1"
}

# Called with a CUE path and its directory. Prints NUL-separated FLAC paths.
resolve_flacs() {
  local cue=$1 cue_dir=$2
  local -a refs=() all=()
  local -A seen=()
  local ref path found base
  local count=0

  mapfile -t refs < <(extract_file_refs "$cue")

  for ref in "${refs[@]}"; do
    ref=${ref//\\//}
    [[ ${ref,,} == *.flac ]] || continue

    if [[ $ref = /* ]]; then
      path=$ref
    else
      path="$cue_dir/$ref"
    fi

    # Rips made on Windows often have the wrong case in the FILE line.
    if [[ ! -f $path && $ref != */* ]]; then
      found=$(find "$cue_dir" -maxdepth 1 -type f -iname "$ref" -print -quit 2>/dev/null || true)
      [[ -n $found ]] && path=$found
    fi

    if [[ ! -f $path ]]; then
      warn "$cue: referenced FLAC not found: $ref"
      continue
    fi

    if [[ -z ${seen["$path"]+x} ]]; then
      seen["$path"]=1
      printf '%s\0' "$path"
      count=$((count + 1))
    fi
  done

  ((count > 0)) && return 0

  # No usable FILE entry: try the CUE's own name, then a lone FLAC beside it.
  base=$(basename -- "$cue")
  base=${base%.[cC][uU][eE]}
  path="$cue_dir/$base.flac"

  if [[ ! -f $path ]]; then
    found=$(find "$cue_dir" -maxdepth 1 -type f -iname "$base.flac" -print -quit 2>/dev/null || true)
    [[ -n $found ]] && path=$found
  fi

  if [[ -f $path ]]; then
    printf '%s\0' "$path"
    return 0
  fi

  mapfile -d '' -t all < <(find "$cue_dir" -maxdepth 1 -type f -iname '*.flac' -print0 2>/dev/null)
  if ((${#all[@]} == 1)); then
    printf '%s\0' "${all[0]}"
  fi
}

# 0 = CD quality, 1 = not CD quality, 2 = could not read the FLAC.
is_cd_quality() {
  local flac=$1 props
  local -a v=()

  if ! props=$(metaflac --show-sample-rate --show-channels --show-bps -- "$flac" 2>/dev/null); then
    return 2
  fi

  mapfile -t v <<< "$props"
  if [[ ${v[0]:-} == 44100 && ${v[1]:-} == 2 && ${v[2]:-} == 16 ]]; then
    return 0
  fi
  return 1
}

process_cue() {
  local cue=$1
  local cue_dir cue_name
  local -a flacs=()
  local flac tracks outdir q

  candidates=$((candidates + 1))
  cue_dir=$(dirname -- "$cue")
  cue_name=$(basename -- "$cue")
  cue_name=${cue_name%.[cC][uU][eE]}

  mapfile -d '' -t flacs < <(resolve_flacs "$cue" "$cue_dir")

  if ((${#flacs[@]} == 0)); then
    warn "$cue: no corresponding FLAC file found, skipping"
    skipped_albums=$((skipped_albums + 1))
    return 0
  fi

  if ((${#flacs[@]} > 1)); then
    warn "$cue: references ${#flacs[@]} FLAC files (multi-file CUE), which is usually already split; skipping"
    skipped_albums=$((skipped_albums + 1))
    return 0
  fi

  flac=${flacs[0]}
  tracks=$(count_tracks "$cue")
  if ((tracks == 0)); then
    warn "$cue: no AUDIO tracks in CUE sheet, skipping"
    skipped_albums=$((skipped_albums + 1))
    return 0
  fi

  if [[ -n $outbase ]]; then
    outdir="$outbase/$cue_name"
  else
    outdir=$cue_dir
  fi

  if is_cd_quality "$flac"; then
    q=0
  else
    q=$?
  fi

  if ((q == 2)); then
    warn "$cue: cannot read FLAC properties: $flac"
    failed_albums=$((failed_albums + 1))
    return 1
  fi

  if ((q == 1)) && ((noncd == 0)); then
    warn "$cue: '$flac' is not CD quality (44100 Hz / 2 channels / 16 bit)."
    warn "  CUE split points are CD-timed, so shnsplit would cut at wrong offsets;"
    warn "  skipping (use --noncd to try anyway)."
    skipped_albums=$((skipped_albums + 1))
    return 0
  fi

  if ((dry_run)); then
    printf '[dry-run] %s\n' "$cue"
    printf '          image:  %s\n' "$flac"
    printf '          tracks: %d\n' "$tracks"
    printf '          output: %s\n' "$outdir"
    albums_ok=$((albums_ok + 1))
    return 0
  fi

  info "Splitting: $cue"
  info "  image:  $flac"
  info "  output: $outdir"

  if ! mkdir -p -- "$outdir"; then
    error "$cue: cannot create output directory: $outdir"
    failed_albums=$((failed_albums + 1))
    return 1
  fi

  if ! tmp=$(mktemp -d "$outdir/.shnsplit.XXXXXX"); then
    error "$cue: cannot create a temporary directory in: $outdir"
    failed_albums=$((failed_albums + 1))
    return 1
  fi

  if ! shnsplit -O always -f "$cue" -t "$template" -o "$format" -d "$tmp" -- "$flac"; then
    error "$cue: shnsplit failed"
    rm -rf -- "$tmp"
    tmp=''
    failed_albums=$((failed_albums + 1))
    return 1
  fi

  local -a produced=()
  mapfile -d '' -t produced < <(find "$tmp" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z -V)

  if ((${#produced[@]} == 0)); then
    error "$cue: shnsplit produced no output files"
    rm -rf -- "$tmp"
    tmp=''
    failed_albums=$((failed_albums + 1))
    return 1
  fi

  if ((tag)) && [[ ${format,,} == flac* ]]; then
    if command -v cuetag >/dev/null 2>&1 && command -v cueprint >/dev/null 2>&1; then
      if ! cuetag "$cue" "${produced[@]}"; then
        warn "$cue: cuetag failed; tracks are untagged"
      fi
    elif ((tag_warned == 0)); then
      warn "cuetag/cueprint not found; FLAC tags will not be written (install cuetools)"
      tag_warned=1
    fi
  fi

  local f dest moved=0 kept=0 move_failed=0
  for f in "${produced[@]}"; do
    dest="$outdir/$(basename -- "$f")"
    if [[ -d $dest ]]; then
      error "cannot overwrite directory with a track file: $dest"
      move_failed=1
      continue
    fi
    if [[ -e $dest ]] && ((force == 0)); then
      warn "exists, not overwriting: $dest"
      kept=$((kept + 1))
      continue
    fi
    if ! mv -f -- "$f" "$dest"; then
      error "failed to move track into place: $dest"
      move_failed=1
      continue
    fi
    moved=$((moved + 1))
  done

  rm -rf -- "$tmp"
  tmp=''

  tracks_written=$((tracks_written + moved))
  if ((kept)); then
    info "  wrote $moved of $tracks track(s), skipped $kept existing file(s)"
  else
    info "  wrote $moved track(s)"
  fi

  if ((move_failed)); then
    failed_albums=$((failed_albums + 1))
    return 1
  fi

  albums_ok=$((albums_ok + 1))
}

main() {
  local -a roots=()
  local cue

  while (($#)); do
    case $1 in
      -n|--dry-run)
        dry_run=1
        shift
        ;;
      -f|--force)
        force=1
        shift
        ;;
      -d|--output-dir)
        (($# >= 2)) || die "option $1 requires an argument"
        outbase=$2
        shift 2
        ;;
      -t|--template)
        (($# >= 2)) || die "option $1 requires an argument"
        template=$2
        shift 2
        ;;
      -o|--format)
        (($# >= 2)) || die "option $1 requires an argument"
        format=$2
        shift 2
        ;;
      --noncd)
        noncd=1
        shift
        ;;
      --no-tag)
        tag=0
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        while (($#)); do
          roots+=("$1")
          shift
        done
        ;;
      -*)
        die "unknown option: $1 (try --help)"
        ;;
      *)
        roots+=("$1")
        shift
        ;;
    esac
  done

  if ((${#roots[@]} == 0)); then
    roots=('.')
  fi

  local root
  for root in "${roots[@]}"; do
    [[ -d $root ]] || die "not a directory: $root"
  done

  require_deps

  while IFS= read -r -d '' cue; do
    process_cue "$cue" || true
  done < <(find "${roots[@]}" -type f -iname '*.cue' -print0 | sort -z)

  if ((candidates == 0)); then
    warn "no .cue files found under: ${roots[*]}"
    return 0
  fi

  printf '\n'
  if ((dry_run)); then
    info "Dry run: $candidates CUE file(s), $albums_ok album(s) would be split."
  else
    info "Found $candidates CUE file(s); wrote $tracks_written track(s) from $albums_ok album(s)."
  fi
  if ((skipped_albums)); then
    info "Skipped $skipped_albums CUE file(s)."
  fi
  if ((failed_albums)); then
    error "$failed_albums CUE file(s) failed."
    return 1
  fi
  return 0
}

main "$@"

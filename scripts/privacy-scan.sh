#!/bin/bash
# Scans the working tree for traces that identify a person or machine.
# Two layers: generic patterns shipped with the repo, plus optional local
# markers in .privacy-markers (gitignored) for names and project slugs.
set -uo pipefail
cd "$(dirname "$0")/.."

PATTERNS=(
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'
  '/Users/[A-Za-z0-9._-]+'
  '/Volumes/[A-Za-z0-9._-]+'
  '~/Documents/Code'
)
# Matches that are allowed to appear.
ALLOW='noreply@|users\.noreply\.github\.com|example\.(com|org|net)'

found=0

# git grep --untracked covers tracked AND new files while honouring
# .gitignore, so data/ and output/ stay out. Plain grep over a word-split
# file list would break on spaces and silently skip untracked files, which
# is exactly the file most likely to leak.
# -o prints the match alone, so ALLOW is judged per match instead of per
# line. A line carrying an allowed address next to a real path cannot slip
# through that way.
scan() {  # $1 = grep flags, $2 = pattern, $3 = label
  hits=$(git grep --untracked --no-color -Ino $1 -e "$2" -- . 2>/dev/null \
         | grep -v '^scripts/privacy-scan\.sh:' \
         | grep -vE "$ALLOW")
  if [ -n "$hits" ]; then
    echo "$3: $2"; echo "$hits" | sed 's/^/  /'; found=1
  fi
}

for pat in "${PATTERNS[@]}"; do
  scan -E "$pat" "PATTERN"
done

if [ -f .privacy-markers ]; then
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    case "$m" in \#*) continue ;; esac
    scan -iF "$m" "MARKER"
  done < .privacy-markers
fi

if [ "$found" -eq 0 ]; then echo "privacy-scan: clean"; fi
exit $found

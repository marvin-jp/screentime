#!/bin/bash
# Verifies the scan actually detects something.
# A silent command and a clean repo look identical; this tells them apart.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

# 1. Clean repo must pass.
if ! scripts/privacy-scan.sh >/dev/null 2>&1; then
  echo "FAIL: scan reports findings on a clean repo"; fail=1
else
  echo "ok: clean repo passes"
fi

# 2. A planted marker must be found. The home-path probe is assembled at
# runtime so this test file does not itself contain the pattern it plants.
trap 'rm -f .scan-probe.md' EXIT
printf 'contact: someone@example.com\npath: /%s/someone/notes\n' "Users" > .scan-probe.md
if scripts/privacy-scan.sh >/dev/null 2>&1; then
  echo "FAIL: scan missed a planted marker"; fail=1
else
  echo "ok: planted marker detected"
fi
rm -f .scan-probe.md

# 3. Clean again after removal.
if ! scripts/privacy-scan.sh >/dev/null 2>&1; then
  echo "FAIL: scan still reports after the probe was removed"; fail=1
else
  echo "ok: clean again"
fi

exit $fail

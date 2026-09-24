#!/bin/bash
# Pushes this build's result (status, deduplicated errors, downscaled screenshots, app log) to the
# `ci-results` branch, so work can continue from the result without opening Codemagic. Each run
# replaces the branch with one fresh commit. Needs GITHUB_TOKEN (Codemagic env group "github"): a
# fine-grained token with Contents read/write on this repo only. Without it, this is a no-op.
set +e
[ -n "$GITHUB_TOKEN" ] || { echo "GITHUB_TOKEN not set; results stay in Codemagic only"; exit 0; }
STATUS=${1:-unknown}
OUT=$(mktemp -d)
mkdir -p "$OUT/shots"
{
  echo "status: $STATUS"
  echo "commit: ${CM_COMMIT:-$(git rev-parse HEAD)}"
  echo "branch: ${CM_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
  echo "build: ${CM_BUILD_ID:-local}"
  date -u "+finished: %Y-%m-%dT%H:%M:%SZ"
} > "$OUT/STATUS.txt"
for f in build.log test.log; do
  [ -f "$f" ] || continue
  echo "=== $f: unique errors ===" >> "$OUT/errors.txt"
  grep -E "error:" "$f" | sed -E 's|^.*/clone/||; s|^.*/zano-app/||' | sort -u | head -150 >> "$OUT/errors.txt"
  tail -40 "$f" > "$OUT/${f%.log}-tail.txt"
done
if [ -d shots ]; then
  for p in shots/*.png; do
    [ -f "$p" ] || continue
    sips -Z 1400 "$p" --out "$OUT/shots/$(basename "$p")" >/dev/null 2>&1 || cp "$p" "$OUT/shots/"
  done
  cp shots/*.log shots/*.ips shots/*.crash "$OUT/shots/" 2>/dev/null
fi
cd "$OUT"
git init -q
git checkout -q -b ci-results
git add -A
git -c user.name="Codemagic" -c user.email="ci@zano.invalid" commit -qm "CI results: $STATUS (${CM_COMMIT:0:7})"
git push -q -f "https://x-access-token:${GITHUB_TOKEN}@github.com/brandongraff-dev/zano-app.git" ci-results && echo "Pushed results to ci-results"
exit 0

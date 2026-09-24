#!/bin/bash
# Screenshot tour on the iOS Simulator, shared by Codemagic (codemagic.yaml). Mirrors the
# "Screenshot tour" step in .github/workflows/ci.yml. Never fails the build: a launch crash or a
# missing screen must not mask the build result.
#   SCREENS     space-separated -ZANOScreen names (default: the main screens)
#   SE_SCREENS  the same, for the iPhone SE pass (default: tab-today)
set +e
mkdir -p shots
APP=$(find build/DerivedData/Build/Products -maxdepth 3 -name "ZANO.app" | head -1)
echo "APP=$APP"
[ -n "$APP" ] || { echo "No app bundle; skipping screenshots"; exit 0; }

pick_sim() {
  xcrun simctl list devices available -j | python3 -c "
import json, re, sys
data = json.load(sys.stdin)['devices']
want = sys.argv[1]
def ver(k):
    m = re.search(r'iOS-(\d+)-(\d+)', k)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)
for k in sorted((k for k in data if 'iOS' in k), key=ver, reverse=True):
    phones = [d for d in data[k] if d['name'].startswith('iPhone')]
    if want == 'se':
        pick = [d for d in phones if d['name'].startswith('iPhone SE')]
    else:
        pick = [d for d in phones if d['name'].endswith(' Pro')] or phones
    if pick:
        print(pick[0]['udid']); break
" "$1"
}

tour() {
  local SIM=$1 PREFIX=$2; shift 2
  xcrun simctl boot "$SIM"
  xcrun simctl bootstatus "$SIM" -b
  xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100
  xcrun simctl install "$SIM" "$APP"
  for SCREEN in "$@"; do
    xcrun simctl terminate "$SIM" com.zano.app 2>/dev/null
    xcrun simctl launch "$SIM" com.zano.app -ZANOScreen "$SCREEN" || echo "LAUNCH FAILED: $SCREEN"
    sleep 5
    xcrun simctl io "$SIM" screenshot "shots/$PREFIX$SCREEN.png"
  done
}

SCREENS=${SCREENS:-"onboarding-1 onboarding-10 onboarding-14 paywall tab-today tab-lock tab-fuel tab-progress tab-settings celebration recap"}
SE_SCREENS=${SE_SCREENS:-"tab-today"}

SIM_ID=$(pick_sim pro)
echo "Simulator: $SIM_ID"
tour "$SIM_ID" "" $SCREENS
xcrun simctl spawn "$SIM_ID" log show --style compact --last 3m --predicate 'process == "ZANO"' > shots/app.log 2>&1
cp ~/Library/Logs/DiagnosticReports/ZANO* shots/ 2>/dev/null

SE_ID=$(pick_sim se)
if [ -n "$SE_ID" ] && [ -n "$SE_SCREENS" ]; then
  tour "$SE_ID" "se-" $SE_SCREENS
fi
ls -la shots
exit 0

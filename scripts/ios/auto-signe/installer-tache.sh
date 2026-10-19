#!/bin/bash
# Installe (ou retire, avec --retirer) la tâche planifiée qui lance
# renouveler-zeron.sh chaque jour à 12 h 30 et à l'ouverture de session. Le
# script ne réinstalle que si la dernière pose a 3 jours ou plus ; un Mac en
# veille à l'heure dite rattrape le passage à son réveil.
set -euo pipefail

label=fr.cyberial.zeron-ios
plist="$HOME/Library/LaunchAgents/$label.plist"
script="$(cd "$(dirname "$0")" && pwd)/renouveler-zeron.sh"
journal="$HOME/Library/Logs/zeron-ios.log"

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
if [ "${1:-}" = "--retirer" ]; then
  rm -f "$plist"
  echo "Tâche retirée."
  exit 0
fi

chmod +x "$script"
mkdir -p "$(dirname "$plist")"
cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$script</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>12</integer><key>Minute</key><integer>30</integer></dict>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$journal</string>
  <key>StandardErrorPath</key><string>$journal</string>
</dict>
</plist>
EOF
plutil -lint "$plist" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Tâche installée : $plist"
echo "Journal : $journal"

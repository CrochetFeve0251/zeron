#!/bin/bash
# Compile Zeron pour iPhone avec le compte Apple GRATUIT de ce Mac, le signe
# (Apple limite le profil à 7 jours) et l'installe sur le téléphone, par le
# Wi-Fi une fois l'iPhone appairé. Rien d'autre qu'Xcode : pas d'outil tiers.
#
#   renouveler-zeron.sh            réinstalle si la dernière pose a 3 jours ou plus
#   renouveler-zeron.sh --force    réinstalle tout de suite
#
# Réglages (facultatifs) dans ~/.config/zeron-ios/config, au format shell :
#   ZERON_TEAM=ABCDE12345           équipe « Personal Team » (devinée si une seule)
#   ZERON_DEVICE="iPhone de …"      nom ou UDID de l'iPhone (deviné si un seul)
#   ZERON_BUNDLE_PREFIX=local.moi.zeron
#   ZERON_REPO_URL=https://github.com/zeronsh/zeron.git
#   ZERON_REF=main                  branche, tag ou commit à compiler
#   ZERON_REPO_DIR=~/zeron-ios      clone dédié : le script le remet à zéro
#   ZERON_MAX_AGE_DAYS=3
set -euo pipefail

CONFIG_DIR="$HOME/.config/zeron-ios"
[ -f "$CONFIG_DIR/config" ] && . "$CONFIG_DIR/config"
REPO_URL="${ZERON_REPO_URL:-https://github.com/zeronsh/zeron.git}"
REF="${ZERON_REF:-main}"
DIR="${ZERON_REPO_DIR:-$HOME/zeron-ios}"
TEAM="${ZERON_TEAM:-}"
DEVICE="${ZERON_DEVICE:-}"
MAX_AGE_DAYS="${ZERON_MAX_AGE_DAYS:-3}"
STATE="$CONFIG_DIR/derniere-installation"
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

log() { echo "[$(date '+%F %T')] $*"; }
echec() {
  log "ÉCHEC : $*" >&2
  osascript -e "display notification \"$*\" with title \"Zeron iPhone : renouvellement raté\"" 2>/dev/null || true
  exit 1
}
trap 'echec "ligne $LINENO : $BASH_COMMAND"' ERR

if [ "${1:-}" != "--force" ] && [ -f "$STATE" ]; then
  age=$(( ($(date +%s) - $(cat "$STATE")) / 86400 ))
  if [ "$age" -lt "$MAX_AGE_DAYS" ]; then
    log "Installée il y a $age jour(s) : rien à faire."
    exit 0
  fi
fi

# Les outils sélectionnés peuvent être les seuls Command Line Tools (sans
# devicectl ni signature pour iPhone) : utiliser l'app Xcode directement.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcode-select -p 2>/dev/null | grep -q '\.app/'; then
  for x in /Applications/Xcode.app /Applications/Xcode-beta.app /Applications/Xcode*.app; do
    if [ -d "$x/Contents/Developer" ]; then
      export DEVELOPER_DIR="$x/Contents/Developer"
      break
    fi
  done
fi
xcrun --find devicectl >/dev/null 2>&1 \
  || echec "Xcode introuvable : installe-le, ou choisis-le avec sudo xcode-select -s /Applications/Xcode.app"
log "Xcode : ${DEVELOPER_DIR:-$(xcode-select -p)}"
command -v rustup >/dev/null || echec "rustup introuvable (https://rustup.rs)"
rustup target add aarch64-apple-ios >/dev/null

# Équipe : la « Personal Team » du compte Apple ajouté dans Xcode → Réglages
# → Comptes. Lue dans les réglages d'Xcode, sinon dans le champ OU des
# certificats « Apple Development » du trousseau.
teams_from_xcode() {
  defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -nE 's/.*teamID = "?([A-Z0-9]{10})"?;.*/\1/p' || true
}
teams_from_certificates() {
  local dir c
  dir=$(mktemp -d)
  security find-certificate -a -c "Apple Development" -p 2>/dev/null \
    | awk -v d="$dir" '/BEGIN CERT/{n++} n{print > (d "/" n ".pem")}' || true
  for c in "$dir"/*.pem; do
    [ -e "$c" ] || continue
    openssl x509 -in "$c" -noout -subject 2>/dev/null \
      | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' || true
  done
  rm -rf "$dir"
}
if [ -z "$TEAM" ]; then
  teams=$( { teams_from_xcode; teams_from_certificates; } | sort -u)
  case "$(printf '%s\n' "$teams" | grep -c . || true)" in
    1) TEAM="$teams" ;;
    0) echec "équipe Apple introuvable : crée un certificat (Xcode → Réglages → Comptes → Gérer les certificats → + → Apple Development) ou mets ZERON_TEAM dans $CONFIG_DIR/config" ;;
    *) echec "plusieurs équipes ($(echo $teams)) : mets ZERON_TEAM=… dans $CONFIG_DIR/config" ;;
  esac
fi
PREFIX="${ZERON_BUNDLE_PREFIX:-local.$(printf '%s' "$TEAM" | tr '[:upper:]' '[:lower:]').zeron}"

# iPhone : appairé (une première fois en USB), puis joignable par le Wi-Fi.
devices="$(mktemp)"
xcrun devicectl list devices --json-output "$devices" >/dev/null
core_id="" udid=""
i=0
while name=$(plutil -extract "result.devices.$i.deviceProperties.name" raw "$devices" 2>/dev/null); do
  id=$(plutil -extract "result.devices.$i.identifier" raw "$devices")
  hw=$(plutil -extract "result.devices.$i.hardwareProperties.udid" raw "$devices" 2>/dev/null || true)
  platform=$(plutil -extract "result.devices.$i.hardwareProperties.platform" raw "$devices" 2>/dev/null || true)
  i=$((i + 1))
  [ "$platform" = "iOS" ] || continue
  if [ -z "$DEVICE" ] || [ "$DEVICE" = "$name" ] || [ "$DEVICE" = "$hw" ] || [ "$DEVICE" = "$id" ]; then
    [ -z "$core_id" ] || echec "plusieurs iPhone : mets ZERON_DEVICE dans $CONFIG_DIR/config"
    core_id="$id" udid="$hw" device_name="$name"
  fi
done
rm -f "$devices"
[ -n "$core_id" ] || echec "aucun iPhone appairé trouvé${DEVICE:+ ($DEVICE)}"
log "iPhone : $device_name ($udid) ; équipe $TEAM ; identifiant $PREFIX"

# Clone dédié, remis exactement sur $REF à chaque passage (les caches de
# compilation, ignorés par git, restent).
[ -d "$DIR/.git" ] || git clone --quiet "$REPO_URL" "$DIR"
cd "$DIR"
git remote set-url origin "$REPO_URL"
git fetch --quiet origin "$REF"
git checkout --quiet --force --detach FETCH_HEAD
log "Source : $REPO_URL $REF ($(git rev-parse --short HEAD))"

# Le projet est signé pour l'équipe de Zeron : on le passe sur la tienne, avec
# tes propres identifiants d'app, et sans les notifications push (un compte
# gratuit ne peut pas les signer).
pbx=apps/ios/Zeron.xcodeproj/project.pbxproj
sed -i '' \
  -e "s/DEVELOPMENT_TEAM = 5XY3M483YQ;/DEVELOPMENT_TEAM = $TEAM;/" \
  -e "/PRODUCT_BUNDLE_IDENTIFIER/s/sh\.zeron\.ios/$PREFIX/" \
  -e '/CODE_SIGN_ENTITLEMENTS = Zeron.entitlements;/d' \
  "$pbx"

# build-core.sh lance cargo dans un environnement vidé (env -i) : sans
# xcode-select vers Xcode, il perdrait le DEVELOPER_DIR choisi plus haut et ne
# trouverait pas le SDK iphoneos.
if [ -n "${DEVELOPER_DIR:-}" ]; then
  sed -i '' "s|^  env -i HOME=|  env -i DEVELOPER_DIR=\"$DEVELOPER_DIR\" HOME=|" scripts/ios/build-core.sh
  grep -q 'env -i DEVELOPER_DIR=' scripts/ios/build-core.sh \
    || echec "build-core.sh a changé : lance sudo xcode-select -s $DEVELOPER_DIR"
fi

# Un profil de 7 jours tout neuf : on retire ceux en cache pour ces identifiants.
for d in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" \
         "$HOME/Library/MobileDevice/Provisioning Profiles"; do
  [ -d "$d" ] || continue
  for p in "$d"/*.mobileprovision; do
    [ -e "$p" ] || continue
    if security cms -D -i "$p" 2>/dev/null | grep -c "$PREFIX" >/dev/null; then rm -f "$p"; fi
  done
done

derived="$DIR/.derived"
rm -rf "$derived/Build/Products"
log "Compilation (la première prend longtemps : tout le cœur Rust)…"
xcodebuild -project apps/ios/Zeron.xcodeproj -scheme Zeron -configuration Release \
  -destination "platform=iOS,id=$udid" -derivedDataPath "$derived" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build -quiet

app="$derived/Build/Products/Release-iphoneos/Zeron.app"
expire=$(security cms -D -i "$app/embedded.mobileprovision" | plutil -extract ExpirationDate raw -)
log "Signée jusqu'au $expire ; installation…"
xcrun devicectl device install app --device "$core_id" "$app" >/dev/null
date +%s > "$STATE"
log "Zeron installé sur $device_name (valable jusqu'au $expire)."

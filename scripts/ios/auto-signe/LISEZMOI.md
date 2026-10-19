# Zeron sur ton iPhone, signé par ton Mac (compte Apple gratuit)

Xcode compile Zeron, le signe avec ton identifiant Apple gratuit et l'installe
sur l'iPhone. Apple limite cette signature à 7 jours : une tâche planifiée la
refait toute seule. Aucun outil tiers, seulement Xcode.

Ce que tu perds par rapport à l'app officielle (TestFlight) : les
notifications de sessions (elles ne partent que vers l'app de Zeron).

## Prérequis

- Un Mac avec **Xcode 26** ou plus, et Rust : `curl https://sh.rustup.rs -sSf | sh`
- Un iPhone sous **iOS 26** ou plus
- Un identifiant Apple, ajouté dans **Xcode → Réglages → Comptes**

## Une seule fois

1. **Branche l'iPhone en USB**, déverrouille-le et accepte « Se fier à cet ordinateur ».
2. Dans Xcode, **Window → Devices and Simulators** : sélectionne l'iPhone et coche
   **Connect via network** (les renouvellements passeront par le Wi-Fi).
3. Sur l'iPhone, active le **mode développeur** : Réglages → Confidentialité et
   sécurité → Mode développeur (le téléphone redémarre).
4. Récupère ces scripts et lance la première installation, à la main :

   ```sh
   git clone -b mac-self-sign https://github.com/CrochetFeve0251/zeron.git ~/zeron-scripts
   ~/zeron-scripts/scripts/ios/auto-signe/renouveler-zeron.sh --force
   ```

   La première compilation est longue (tout le cœur Rust). Si macOS demande
   l'accès au trousseau pour `codesign`, réponds **Toujours autoriser** : sinon
   la tâche planifiée restera bloquée sur cette question.
5. Sur l'iPhone, la première fois : Réglages → Général → **VPN et gestion de
   l'appareil** → ton identifiant → **Faire confiance**.
6. Installe la tâche planifiée :

   ```sh
   ~/zeron-scripts/scripts/ios/auto-signe/installer-tache.sh
   ```

## Ensuite

Chaque jour à 12 h 30 (ou au réveil du Mac), le script regarde la date de la
dernière installation et réinstalle à partir de 3 jours : il reste toujours de
la marge sur les 7. Il suffit que le Mac soit allumé, avec ta session ouverte,
et l'iPhone sur le même Wi-Fi. Un échec affiche une notification sur le Mac.

- Journal : `~/Library/Logs/zeron-ios.log`
- Forcer maintenant : `renouveler-zeron.sh --force`
- Retirer la tâche : `installer-tache.sh --retirer`

## Réglages

Dans `~/.config/zeron-ios/config` (facultatif) :

```sh
ZERON_TEAM=ABCDE12345            # si Xcode connaît plusieurs équipes
ZERON_DEVICE="iPhone de Cyrille" # si plusieurs iPhone sont appairés
ZERON_REF=main                   # la version à compiler
# Une autre source, par exemple une branche de ton fork :
# ZERON_REPO_URL=https://github.com/CrochetFeve0251/zeron.git
# ZERON_REF=ma-branche
```

Le script compile dans un clone dédié (`~/zeron-ios`) qu'il remet à zéro à
chaque passage : n'y travaille pas.

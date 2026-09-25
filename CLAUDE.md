# sftp-docker

Serveur SFTP seul (OpenSSH sur Debian `trixie-slim`), un chroot par utilisateur, publié sur GHCR.

## Repo GitHub

- **Repo** : `Greite/sftp-docker`
- **Image** : `ghcr.io/greite/sftp-docker:latest`

## Structure

- `Dockerfile` : `debian:trixie-slim` + `apt-get upgrade` + `openssh-server` + `HEALTHCHECK`
  - sans le upgrade, le check `apt list --upgradable` de la CI rebuildrait en boucle dès qu'un paquet de la base est en retard
  - le healthcheck lit `/proc/net/tcp` au lieu de se connecter : un test TCP sur le port 22 écrit 3 lignes de log par contrôle, et un `Match Address … LogLevel QUIET` ne les cache pas (écrites avant l'évaluation du Match)
- `entrypoint.sh` : crée les utilisateurs depuis `/config/sshd/users.conf` (format atmoz/sftp), génère les clés d'hôte si elles manquent, puis lance `sshd -D -e` (stderr passe par une fifo qui préfixe la date, `$TZ` ; sshd reste PID 1)
- `sshd_config` : SFTP seul, chroot `%h`, `PerSourcePenalties` à la place de fail2ban, `Include /config/sshd/sshd_config.d/*.conf` pour les réglages propres au site (Match)
- Caps minimales testées : `SETUID SETGID SYS_CHROOT CHOWN` + `no-new-privileges` (le README les montre dans le quick start)
- `logo.svg` / `logo.png` : logo (PNG 512 px rendu depuis le SVG via Chrome headless)
- `.github/workflows/build.yml` : build multi-plateforme (amd64/arm64), push sur GHCR
  - Déclenché sur push (main), tags `v*` (CalVer `vYYYY.MM`), cron 4 fois par jour, ou manuellement
  - Rebuild si `debian:trixie-slim` a bougé (`lucacome/docker-image-update-checker`) **ou** si `apt list --upgradable` n'est pas vide dans l'image publiée (openssh-server n'est pas dans l'image de base)

## Git (historique linéaire, une seule branche permanente)

- `main` : seule branche permanente. Chaque release est un tag annoté `vYYYY.MM` (CalVer, `vYYYY.MM.N` pour un correctif) sur `main`, avec une release GitHub aux notes écrites à la main en anglais (New / Changes / Upgrading). Le tag déclenche la publication de l'image sur GHCR.
- Tout travail part de `main` sur une branche `feature/<sujet>` (ou `fix/<sujet>`), rebasée sur `main` puis intégrée en fast-forward : pas de commit de merge, pas de branche `develop`.
- Jamais de commit direct sur `main`.
- Messages en anglais, conventional commits : `feat:`, `fix:`, `docs:`, `ci:`, `chore:`, `refactor:`.

## Contraintes

- **Dépôt public : aucune donnée personnelle ici** (pas de prénoms, de noms de machines, d'adresses, de noms de produits ou de conteneurs tiers). Le contexte d'exploitation reste hors du dépôt.
- Les clients existants ne doivent jamais avoir à être reconfigurés : ne pas toucher au format `users.conf` ni aux `KexAlgorithms`/`Ciphers` figés (OpenSSH 10 a retiré les KEX `diffie-hellman-*`).
- Le home chrooté doit appartenir à root et ne pas être modifiable par les autres : les partages se montent en dessous.

## Test local

```bash
docker build -t sftp .
mkdir -p /tmp/sftp/sshd && echo "bob:secret:1001:100" > /tmp/sftp/sshd/users.conf
docker run --rm -p 2222:22 -v /tmp/sftp:/config -v /tmp/share:/home/bob/share sftp
sftp -P 2222 bob@localhost
```

#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

readonly INSTALLER_VERSION="1.0.0"
readonly INSTALL_DIR="/opt/email-automation"
readonly STATE_DIR="/var/lib/email-automation"
readonly BACKUP_DIR="/var/backups/email-automation"
readonly RELEASE_BASE_URL="${EMAIL_AUTOMATION_RELEASE_BASE_URL:-https://benson8lany.github.io/GlobalFrontDesk-Deploy}"
readonly EMBEDDED_RELEASE_KEY_BASE64="LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUNvd0JRWURLMlZ3QXlFQWpyN1VNS1pDM3JKWUV3dk9WNDBiS1FiR3pZUkpSQkxuNWdUOEMxdk9DYUU9Ci0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQo="
readonly UNCONFIGURED_HOST='<INSTALL''_HOST>'
readonly UNCONFIGURED_KEY='__RELEASE''_PUBLIC_KEY_BASE64__'

die() { printf 'Installation failed: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }
[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Run the one-line installer through sudo."

[[ "$RELEASE_BASE_URL" != *"$UNCONFIGURED_HOST"* ]] || die "This is an unbranded installer template. Publish it with a configured release host first."
[[ "$EMBEDDED_RELEASE_KEY_BASE64" != "$UNCONFIGURED_KEY" ]] || die "This installer has not been rendered with the vendor release public key."

source /etc/os-release
case "${ID:-}" in ubuntu|debian) ;; *) die "V1 supports Ubuntu and Debian only." ;; esac
case "${ID}:${VERSION_ID}" in
  ubuntu:22.04|ubuntu:24.04|debian:12|debian:13) ;;
  *) die "Supported releases are Ubuntu 22.04/24.04 and Debian 12/13." ;;
esac
arch="$(dpkg --print-architecture)"
[[ "$arch" == "amd64" || "$arch" == "arm64" ]] || die "Supported architectures are amd64 and arm64."
[[ "$(nproc)" -ge 2 ]] || die "At least 2 CPU cores are required."
memory_kib="$(awk '/MemTotal/ {print $2}' /proc/meminfo)"
[[ "$memory_kib" -ge 3800000 ]] || die "At least 4 GB RAM is required."
disk_kib="$(df -Pk /opt | awk 'NR==2 {print $4}')"
[[ "$disk_kib" -ge 20971520 ]] || die "At least 20 GB free disk is required under /opt."
command -v systemctl >/dev/null || die "systemd is required."
if [[ -e "$INSTALL_DIR/.env.customer" ]]; then
  die "An installation already exists. Use: sudo email-automation status"
fi

if [[ -z "${EMAIL_AUTOMATION_FQDN:-}" ]]; then
  read -r -p "Customer FQDN (for example mail.company.com): " EMAIL_AUTOMATION_FQDN
fi
if [[ -z "${EMAIL_AUTOMATION_ACME_EMAIL:-}" ]]; then
  read -r -p "Email for TLS certificate notices: " EMAIL_AUTOMATION_ACME_EMAIL
fi
if [[ -z "${EMAIL_AUTOMATION_RELEASE_CHANNEL:-}" ]]; then
  read -r -p "Release channel [stable/preview] (stable): " EMAIL_AUTOMATION_RELEASE_CHANNEL
  EMAIL_AUTOMATION_RELEASE_CHANNEL="${EMAIL_AUTOMATION_RELEASE_CHANNEL:-stable}"
fi
FQDN="${EMAIL_AUTOMATION_FQDN,,}"
ACME_EMAIL="$EMAIL_AUTOMATION_ACME_EMAIL"
RELEASE_CHANNEL="$EMAIL_AUTOMATION_RELEASE_CHANNEL"
[[ "$FQDN" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || die "Enter a valid fully qualified domain name without https:// or a path."
[[ "$ACME_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "Enter a valid ACME contact email."
[[ "$RELEASE_CHANNEL" == "stable" || "$RELEASE_CHANNEL" == "preview" ]] || die "Release channel must be stable or preview."
getent ahosts "$FQDN" >/dev/null || die "$FQDN does not currently resolve in DNS. Point it to this server before installing."
for port in 80 443; do
  if ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .; then die "TCP port $port is already in use."; fi
done

info "Installing verified operating-system dependencies"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq ca-certificates curl jq openssl gnupg lsb-release >/dev/null
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl --proto '=https' --tlsv1.2 -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod 0644 /etc/apt/keyrings/docker.asc
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' "$arch" "$ID" "${VERSION_CODENAME}" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
fi
systemctl enable --now docker >/dev/null

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$INSTALL_DIR/secrets" "$STATE_DIR/manifests" "$STATE_DIR/knowledge-files" "$BACKUP_DIR"
chmod 0750 "$INSTALL_DIR" "$INSTALL_DIR/secrets" "$BACKUP_DIR"
chmod 0755 "$STATE_DIR" "$STATE_DIR/manifests"
chown 1000:1000 "$STATE_DIR/knowledge-files"
chmod 0700 "$STATE_DIR/knowledge-files"
printf '%s' "$EMBEDDED_RELEASE_KEY_BASE64" | base64 -d > "$INSTALL_DIR/release-public-key.pem"
chmod 0644 "$INSTALL_DIR/release-public-key.pem"

info "Verifying the signed $RELEASE_CHANNEL release manifest"
manifest="$tmp/manifest.json"; signature="$tmp/manifest.sig"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$RELEASE_BASE_URL/channels/$RELEASE_CHANNEL/manifest.json" -o "$manifest"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$RELEASE_BASE_URL/channels/$RELEASE_CHANNEL/manifest.sig" -o "$signature"
openssl pkeyutl -verify -pubin -inkey "$INSTALL_DIR/release-public-key.pem" -rawin -in "$manifest" -sigfile "$signature" >/dev/null 2>&1 || die "Release manifest signature is invalid."
jq -e --arg channel "$RELEASE_CHANNEL" '
  (.sequence | type == "number" and . >= 1) and (.channel == $channel) and
  (.version | type == "string") and (.minimumInstallerVersion | type == "string") and
  ([.images.api,.images.worker,.images.web,.images.migrate,.images.postgres,.images.embeddings,.images.caddy] | all(test("@sha256:[a-f0-9]{64}$"))) and
  (.license.publicKeyBase64 | type == "string" and length >= 40)
' "$manifest" >/dev/null || die "Release manifest structure is invalid."
minimum_installer="$(jq -r '.minimumInstallerVersion' "$manifest")"
[[ "$(printf '%s\n%s\n' "$minimum_installer" "$INSTALLER_VERSION" | sort -V | head -1)" == "$minimum_installer" ]] || die "Release requires installer $minimum_installer or newer."
sequence="$(jq -r '.sequence' "$manifest")"
mkdir -p "$STATE_DIR/manifests/$sequence"
install -m 0644 "$manifest" "$STATE_DIR/manifests/$sequence/manifest.json"
install -m 0644 "$signature" "$STATE_DIR/manifests/$sequence/manifest.sig"
printf '%s\n' "$sequence" > "$STATE_DIR/highest-manifest-sequence"

download_bundle_file() {
  local field="$1" destination="$2" url digest actual
  url="$(jq -r ".bundle.$field.url" "$manifest")"; digest="$(jq -r ".bundle.$field.sha256" "$manifest")"
  curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$url" -o "$destination"
  actual="$(sha256sum "$destination" | awk '{print $1}')"
  [[ "$actual" == "$digest" ]] || die "Bundle checksum failed for $field."
}
download_bundle_file compose "$INSTALL_DIR/compose.yaml"
download_bundle_file caddyfile "$INSTALL_DIR/Caddyfile"
download_bundle_file manager "$tmp/email-automation"
download_bundle_file timer "$tmp/email-automation-update.timer"
download_bundle_file service "$tmp/email-automation-update.service"
download_bundle_file imagePublicKey "$INSTALL_DIR/image-public-key.pem"
chmod 0644 "$INSTALL_DIR/compose.yaml" "$INSTALL_DIR/Caddyfile" "$INSTALL_DIR/image-public-key.pem"

cosign_url="$(jq -r ".cosign.$arch.url" "$manifest")"
cosign_sha="$(jq -r ".cosign.$arch.sha256" "$manifest")"
curl --proto '=https' --tlsv1.2 -fsSL --retry 3 "$cosign_url" -o "$tmp/cosign"
[[ "$(sha256sum "$tmp/cosign" | awk '{print $1}')" == "$cosign_sha" ]] || die "Cosign checksum verification failed."
install -m 0755 "$tmp/cosign" /usr/local/bin/cosign

info "Generating customer-owned secrets and recovery identity"
installation_id="$(cat /proc/sys/kernel/random/uuid)"
auth_secret="$(openssl rand -base64 48 | tr -d '\n')"
encryption_key="$(openssl rand -base64 32 | tr -d '\n')"
postgres_owner_password="$(openssl rand -hex 32)"
postgres_runtime_password="$(openssl rand -hex 32)"
setup_bootstrap_token="${EMAIL_AUTOMATION_SETUP_TOKEN:-$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')}"
[[ "$setup_bootstrap_token" =~ ^[A-Za-z0-9_-]{32,128}$ ]] || die "The owner setup token is invalid."
setup_bootstrap_token_hash="$(printf '%s' "$setup_bootstrap_token" | sha256sum | awk '{print $1}')"
gmail_push_token="$(openssl rand -base64 32 | tr -d '\n')"
license_key="$(jq -r '.license.publicKeyBase64' "$manifest")"
control_url="$(jq -r '.license.controlUrl' "$manifest")"
cat > "$INSTALL_DIR/.env.customer" <<EOF
NODE_ENV=production
FQDN=$FQDN
ACME_EMAIL=$ACME_EMAIL
API_PORT=3003
API_BASE_URL=https://$FQDN
WEB_ORIGIN=https://$FQDN
AUTH_SECRET=$auth_secret
ENCRYPTION_KEY_BASE64=$encryption_key
INSTALLATION_ID=$installation_id
LICENSE_CONTROL_URL=$control_url
LICENSE_PUBLIC_KEY_BASE64=$license_key
GMAIL_PUSH_TOKEN=$gmail_push_token
GMAIL_PUBSUB_AUDIENCE=https://$FQDN/webhooks/gmail
GMAIL_PUBSUB_TOPIC=
SMTP_HOST=
SMTP_PROVIDER=custom
SMTP_PORT=587
SMTP_SECURE=false
SMTP_USER=
SMTP_PASSWORD=
SMTP_FROM=
POSTGRES_OWNER_PASSWORD=$postgres_owner_password
POSTGRES_OWNER_USER=mail_owner
POSTGRES_RUNTIME_PASSWORD=$postgres_runtime_password
SETUP_BOOTSTRAP_TOKEN_HASH=$setup_bootstrap_token_hash
EOF
chmod 0600 "$INSTALL_DIR/.env.customer"
cat > "$INSTALL_DIR/release.env" <<EOF
APP_VERSION=$(jq -r '.version' "$manifest")
RELEASE_CHANNEL=$RELEASE_CHANNEL
RELEASE_SEQUENCE=$sequence
RELEASE_BASE_URL=$RELEASE_BASE_URL
STATE_DIR=$STATE_DIR
API_IMAGE=$(jq -r '.images.api' "$manifest")
WORKER_IMAGE=$(jq -r '.images.worker' "$manifest")
WEB_IMAGE=$(jq -r '.images.web' "$manifest")
MIGRATE_IMAGE=$(jq -r '.images.migrate' "$manifest")
POSTGRES_IMAGE=$(jq -r '.images.postgres' "$manifest")
EMBEDDINGS_IMAGE=$(jq -r '.images.embeddings' "$manifest")
CADDY_IMAGE=$(jq -r '.images.caddy' "$manifest")
EOF
chmod 0600 "$INSTALL_DIR/release.env"

if [[ "${EMAIL_AUTOMATION_GCP_REGISTRY_AUTH:-false}" == "true" ]]; then
  info "Authenticating this workspace to the signed release registry"
  export DOCKER_CONFIG="/root/.docker"
  registry_host="$(jq -r '.images.api | split("/")[0]' "$manifest")"
  [[ "$registry_host" == *.pkg.dev ]] || die "The signed release does not use a supported Google Artifact Registry host."
  cat > "$tmp/docker-credential-emailpro-gcp" <<'HELPER'
#!/usr/bin/env bash
set -Eeuo pipefail
case "${1:-}" in
  get)
    IFS= read -r registry || [[ -n "${registry:-}" ]]
    registry="${registry#https://}"
    registry="${registry%%/*}"
    [[ "$registry" == *.pkg.dev ]] || { echo "Unsupported registry" >&2; exit 1; }
    token="$(curl --noproxy '*' -fsS --max-time 8 -H 'Metadata-Flavor: Google' \
      http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token | jq -er '.access_token')"
    jq -nc --arg secret "$token" '{Username:"oauth2accesstoken",Secret:$secret}'
    ;;
  list) printf '{}\n' ;;
  *) echo "Credential persistence is disabled" >&2; exit 1 ;;
esac
HELPER
  install -m 0755 "$tmp/docker-credential-emailpro-gcp" /usr/local/bin/docker-credential-emailpro-gcp
  install -d -m 0700 "$DOCKER_CONFIG"
  printf '%s\n' "$registry_host" | docker-credential-emailpro-gcp get | jq -e '.Username == "oauth2accesstoken" and (.Secret | length > 100)' >/dev/null || die "The workspace could not obtain its short-lived Google registry token."
  if [[ -f "$DOCKER_CONFIG/config.json" ]]; then
    jq --arg registry "$registry_host" 'del(.auths[$registry]) | .credHelpers[$registry] = "emailpro-gcp"' "$DOCKER_CONFIG/config.json" > "$tmp/docker-config.json"
  else
    jq -n --arg registry "$registry_host" '{credHelpers:{($registry):"emailpro-gcp"}}' > "$tmp/docker-config.json"
  fi
  install -m 0600 "$tmp/docker-config.json" "$DOCKER_CONFIG/config.json"
fi

openssl req -x509 -newkey rsa:3072 -nodes -days 3650 -subj "/CN=email-automation-backup-$installation_id" -keyout "$INSTALL_DIR/secrets/backup-identity.pem" -out "$INSTALL_DIR/backup-recipient.crt" >/dev/null 2>&1
chmod 0600 "$INSTALL_DIR/secrets/backup-identity.pem"
chmod 0644 "$INSTALL_DIR/backup-recipient.crt"

info "Verifying signed customer images"
for component in api worker web migrate clientGateway; do
  image="$(jq -r ".images.$component" "$manifest")"
  cosign verify --key "$INSTALL_DIR/image-public-key.pem" "$image" >/dev/null || die "Image signature verification failed for $component."
done

install -m 0755 "$tmp/email-automation" /usr/local/sbin/email-automation
install -m 0644 "$tmp/email-automation-update.timer" /etc/systemd/system/email-automation-update.timer
install -m 0644 "$tmp/email-automation-update.service" /etc/systemd/system/email-automation-update.service
systemctl daemon-reload

compose=(docker compose --project-directory "$INSTALL_DIR" --env-file "$INSTALL_DIR/.env.customer" --env-file "$INSTALL_DIR/release.env" -f "$INSTALL_DIR/compose.yaml")
info "Pulling immutable images and starting the customer plane"
"${compose[@]}" pull
"${compose[@]}" up -d postgres embeddings
migrated=false
for attempt in 1 2 3; do
  if "${compose[@]}" run --rm migrate; then
    migrated=true
    break
  fi
  if [[ "$attempt" -lt 3 ]]; then
    info "Database migration attempt $attempt did not complete; retrying in 10 seconds"
    sleep 10
  fi
done
[[ "$migrated" == true ]] || die "Database migration failed after three attempts. Run: sudo email-automation logs"
"${compose[@]}" up -d api worker web caddy

ready=false
for _ in $(seq 1 45); do
  if curl --proto '=https' --tlsv1.2 -fsS "https://$FQDN/health/ready" >/dev/null 2>&1; then ready=true; break; fi
  sleep 4
done
[[ "$ready" == true ]] || die "Services started, but the public HTTPS health check failed. Run: sudo email-automation logs"
systemctl enable --now email-automation-update.timer >/dev/null
jq -n --arg installed "$(jq -r '.version' "$manifest")" --arg channel "$RELEASE_CHANNEL" '{installedVersion:$installed,channel:$channel,availableVersion:$installed,updateAvailable:false,checkedAt:(now|todateiso8601),state:"current"}' > "$STATE_DIR/update-status.json"
chmod 0644 "$STATE_DIR/update-status.json"

info "Installation complete"
if [[ -n "${EMAIL_AUTOMATION_SETUP_TOKEN:-}" ]]; then
  printf 'Open the owner setup link from your Google deployment details.\n'
else
  printf 'One-time owner setup link: https://%s/login#setup=%s\n' "$FQDN" "$setup_bootstrap_token"
fi
printf 'Installation ID: %s\n' "$installation_id"
printf '\nBefore relying on backups, export the recovery identity to secure off-server storage:\n  sudo email-automation recovery-key export /path/to/secure/off-server/storage\n'

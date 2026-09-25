#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

deployment_code_file=""
bootstrap_curl_config=""

cleanup() {
  [[ -z "$deployment_code_file" || ! -f "$deployment_code_file" ]] || rm -f -- "$deployment_code_file"
  [[ -z "$bootstrap_curl_config" || ! -f "$bootstrap_curl_config" ]] || rm -f -- "$bootstrap_curl_config"
}
trap cleanup EXIT

die() { printf 'Deployment stopped: %s\n' "$*" >&2; exit 1; }
info() { printf '\n==> %s\n' "$*"; }

send_bootstrap_status() {
  local body="$1" timestamp nonce signature
  timestamp="$(date +%s)"
  nonce="$(python3 -c 'import uuid; print(uuid.uuid4())')"
  signature="$(
    BOOTSTRAP_BODY="$body" \
    BOOTSTRAP_NONCE="$nonce" \
    BOOTSTRAP_TIMESTAMP="$timestamp" \
    BOOTSTRAP_TOKEN_FILE="$deployment_code_file" \
      python3 -c 'import hashlib,hmac,os; key=open(os.environ["BOOTSTRAP_TOKEN_FILE"],encoding="utf-8").read().encode(); message=(os.environ["BOOTSTRAP_TIMESTAMP"]+"\n"+os.environ["BOOTSTRAP_NONCE"]+"\n"+os.environ["BOOTSTRAP_BODY"]).encode(); print(hmac.new(key,message,hashlib.sha256).hexdigest())'
  )"
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --retry 3 --max-time 15 \
    --config "$bootstrap_curl_config" \
    --request POST \
    --header 'content-type: application/json' \
    --header "x-bootstrap-timestamp: $timestamp" \
    --header "x-bootstrap-nonce: $nonce" \
    --header "x-bootstrap-signature: $signature" \
    --data "$body" \
    "${EMAIL_AUTOMATION_CONTROL_URL:-https://license.globalfrontdesk.com}/v1/bootstrap/status" \
    >/dev/null
}

ensure_terraform() {
  if command -v terraform >/dev/null 2>&1 && terraform version 2>/dev/null | grep -q '^Terraform v'; then
    return
  fi

  local version="1.15.9"
  local architecture archive checksum
  case "$(uname -m)" in
    x86_64)
      architecture="amd64"
      checksum="76edd0b22d2f27d3d2e097cd793209646f719cf60f02ff3af626b07361137da1"
      ;;
    aarch64|arm64)
      architecture="arm64"
      checksum="0afa6c29f61ca5ea270e950e43e50ecf2418b598507bf580e8ae76e1e6699b19"
      ;;
    *)
      die "This Cloud Shell architecture is not supported: $(uname -m)"
      ;;
  esac

  archive="terraform_${version}_linux_${architecture}.zip"
  info "Installing the verified Terraform command in this Cloud Shell session"
  mkdir -p "$HOME/.local/bin"
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    "https://releases.hashicorp.com/terraform/${version}/${archive}" \
    --output "/tmp/${archive}"
  printf '%s  %s\n' "$checksum" "/tmp/${archive}" | sha256sum --check --status \
    || die "Terraform download verification failed."
  unzip -oq "/tmp/${archive}" -d "$HOME/.local/bin"
  rm -f "/tmp/${archive}"
  export PATH="$HOME/.local/bin:$PATH"
  terraform version | head -1 | grep -q '^Terraform v' \
    || die "Terraform could not be installed in Cloud Shell."
}

command -v gcloud >/dev/null || die "Google Cloud CLI is required. Open this installer in Google Cloud Shell."
command -v python3 >/dev/null || die "Python 3 is required in this Cloud Shell session."
ensure_terraform

active_account="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -1)"
[[ -n "$active_account" ]] || die "Sign in to Google Cloud before deploying."

project_id="${1:-${GOOGLE_CLOUD_PROJECT:-${CLOUDSDK_CORE_PROJECT:-}}}"
if [[ -z "$project_id" ]]; then
  project_id="$(gcloud config get-value project 2>/dev/null || true)"
fi
[[ -n "$project_id" && "$project_id" != "(unset)" ]] || die "Select a Google Cloud project in the tutorial first."

installation_id="${2:-${EMAIL_AUTOMATION_INSTALLATION_ID:-}}"
if [[ -z "$installation_id" ]]; then
  read -r -p "Global Front Desk installation ID (starts with gfd-): " installation_id
fi
[[ "$installation_id" =~ ^gfd-[a-f0-9-]{36}$ ]] \
  || die "Copy the installation ID exactly from Global Front Desk onboarding."

read -r -s -p "Temporary deployment code from Global Front Desk: " deployment_code
printf '\n'
[[ ${#deployment_code} -ge 40 ]] || die "The deployment code is invalid. Copy it exactly from onboarding."
deployment_code_file="$(mktemp)"
bootstrap_curl_config="$(mktemp)"
printf '%s' "$deployment_code" > "$deployment_code_file"
printf 'header = "Authorization: Bearer %s"\n' "$deployment_code" > "$bootstrap_curl_config"
chmod 0600 "$deployment_code_file" "$bootstrap_curl_config"
unset deployment_code

authorization_body="$(printf '{\"installationId\":\"%s\"}' "$installation_id")"
send_bootstrap_status "$authorization_body" \
  || die "The installation ID and deployment code could not be verified. No cloud resources were changed."

project_state="$(gcloud projects describe "$project_id" --format='value(lifecycleState)' 2>/dev/null || true)"
[[ "$project_state" == "ACTIVE" ]] || die "The selected project is unavailable: $project_id"

billing_enabled="$(gcloud billing projects describe "$project_id" --format='value(billingEnabled)' 2>/dev/null || true)"
[[ "$billing_enabled" == "True" || "$billing_enabled" == "true" ]] || die "Enable billing for $project_id, then run this step again."

printf '\nGoogle account: %s\nProject: %s\n\n' "$active_account" "$project_id"
read -r -p "Deploy the private Global Front Desk workspace to this project? [y/N] " answer
[[ "$answer" == "y" || "$answer" == "Y" ]] || die "Nothing was changed."

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

info "Preparing the customer-owned deployment"
terraform init -input=false

info "Showing the infrastructure Google will create"
rm -f .deployment.tfplan
terraform plan -input=false -out=.deployment.tfplan -var="project_id=$project_id" -var="installation_id=$installation_id"
[[ -s .deployment.tfplan ]] || die "Terraform did not create a deployment plan. Nothing was changed."

printf '\nThis plan creates one VM, one encrypted disk, a dedicated network, firewall rules, a static IP, and a runtime service account.\n'
read -r -p "Approve this deployment? [y/N] " approve
[[ "$approve" == "y" || "$approve" == "Y" ]] || die "The plan was not applied."

info "Creating the private workspace"
terraform apply -input=false -auto-approve .deployment.tfplan

dashboard_url="$(terraform output -raw dashboard_url)"
owner_setup_url="$(terraform output -raw owner_setup_url)"
cat > deployment-result.txt <<EOF
Private dashboard: $dashboard_url
One-time owner setup: $owner_setup_url
Installation ID: $installation_id
EOF
chmod 0600 deployment-result.txt

installing_body="$(printf '{\"installationId\":\"%s\",\"workspaceUrl\":\"%s\",\"ready\":false}' "$installation_id" "$dashboard_url")"
if ! send_bootstrap_status "$installing_body"; then
  printf 'Warning: Global Front Desk could not receive the initial deployment status. The installer will retry after the workspace is ready.\n'
fi

info "Waiting for the private workspace"
printf 'Google is installing Global Front Desk on the new server. This normally takes 5-10 minutes.\n'
ready=false
for attempt in $(seq 1 90); do
  if curl --proto '=https' --tlsv1.2 -fsS --max-time 10 "$dashboard_url/health/ready" >/dev/null 2>&1; then
    ready=true
    break
  fi
  if (( attempt % 6 == 0 )); then
    printf 'Still installing... (%d minutes elapsed)\n' "$((attempt / 6))"
  fi
  sleep 10
done

if [[ "$ready" != true ]]; then
  printf '\nThe server is still installing. Your links are safe in deployment-result.txt.\n'
  printf 'To check progress, run:\n  %s\n\n' "$(terraform output -raw installation_log_command)"
  exit 1
fi

ready_body="$(printf '{\"installationId\":\"%s\",\"workspaceUrl\":\"%s\",\"ready\":true}' "$installation_id" "$dashboard_url")"
if ! send_bootstrap_status "$ready_body"; then
  printf 'Warning: The workspace is ready, but Global Front Desk did not receive the final status. Keep deployment-result.txt and use Check status in onboarding.\n'
fi

info "Your private workspace is ready"
printf 'Your one-time setup link is saved in:\n  %s/deployment-result.txt\n\n' "$script_dir"
printf 'Open this link now:\n%s\n' "$owner_setup_url"

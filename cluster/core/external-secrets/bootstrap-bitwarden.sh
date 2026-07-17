#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

readonly namespace="external-secrets"
readonly secret_name="bitwarden-cli"
readonly bitwarden_host="${BW_HOST:-https://vault.bitwarden.com}"

command -v kubectl >/dev/null || {
  echo "kubectl is required" >&2
  exit 1
}

context="$(kubectl config current-context)"
printf 'Kubernetes context: %s\nBitwarden server: %s\n' "${context}" "${bitwarden_host}"
read -r -p 'Create or replace the bootstrap Secret in this cluster? [y/N] ' confirm
[[ "${confirm}" == "y" || "${confirm}" == "Y" ]] || exit 1

kubectl get namespace "${namespace}" >/dev/null

umask 077
bootstrap_dir="$(mktemp -d)"
cleanup() {
  unset bw_client_id bw_client_secret bw_password
  if [[ -n "${bootstrap_dir:-}" && -d "${bootstrap_dir}" ]]; then
    rm -rf -- "${bootstrap_dir}"
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s' "${bitwarden_host}" >"${bootstrap_dir}/BW_HOST"
read -r -p 'Bitwarden API client ID: ' bw_client_id
[[ -n "${bw_client_id}" ]] || {
  echo "The API client ID cannot be empty" >&2
  exit 1
}
printf '%s' "${bw_client_id}" >"${bootstrap_dir}/BW_CLIENTID"
read -r -s -p 'Bitwarden API client secret: ' bw_client_secret
printf '\n'
[[ -n "${bw_client_secret}" ]] || {
  echo "The API client secret cannot be empty" >&2
  exit 1
}
printf '%s' "${bw_client_secret}" >"${bootstrap_dir}/BW_CLIENTSECRET"
read -r -s -p 'Bitwarden master password: ' bw_password
printf '\n'
[[ -n "${bw_password}" ]] || {
  echo "The master password cannot be empty" >&2
  exit 1
}
printf '%s' "${bw_password}" >"${bootstrap_dir}/BW_PASSWORD"

kubectl create secret generic "${secret_name}" \
  --namespace "${namespace}" \
  --from-file="${bootstrap_dir}/BW_HOST" \
  --from-file="${bootstrap_dir}/BW_CLIENTID" \
  --from-file="${bootstrap_dir}/BW_CLIENTSECRET" \
  --from-file="${bootstrap_dir}/BW_PASSWORD" \
  --dry-run=client \
  --output=yaml | kubectl apply -f -

printf 'Bootstrap Secret %s/%s is ready.\n' "${namespace}" "${secret_name}"

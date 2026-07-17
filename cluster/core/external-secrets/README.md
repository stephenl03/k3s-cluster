# External Secrets with Bitwarden Password Manager

This deployment uses the regular Bitwarden Password Manager through `bw serve`.
It does not use Bitwarden Secrets Manager.

## Bootstrap the Bitwarden credentials

ESO cannot fetch the credentials that unlock its own Bitwarden provider. Create
the `bitwarden-cli` Secret directly in the cluster and do not commit it to Git.

Create a personal API key from the **Security > Keys** page in the Bitwarden web
vault settings. The API key avoids an interactive two-factor authentication
prompt, but the master password is still required to unlock the vault after
login.

Run the bootstrap script from a trusted workstation:

```bash
./cluster/core/external-secrets/bootstrap-bitwarden.sh
```

Set `BW_HOST` when using self-hosted Bitwarden or Vaultwarden:

```bash
BW_HOST=https://vault.example.com \
  ./cluster/core/external-secrets/bootstrap-bitwarden.sh
```

The script verifies the active Kubernetes context, prompts without echoing the
client secret or master password, and removes its temporary files on exit.
Reloader restarts the provider pod when this Secret is updated. Run the script
again to rotate the API key or master password.

## Allow a namespace to use Bitwarden

Access is opt-in. Add this label to a namespace manifest before creating an
`ExternalSecret` in that namespace:

```yaml
metadata:
  labels:
    external-secrets.io/bitwarden-access: "true"
```

Anyone who can create an `ExternalSecret` in an opted-in namespace can read any
item available to the configured Bitwarden account. Use a dedicated account
with the least vault access needed by the cluster.

## Create an ExternalSecret

Use the Bitwarden item's UUID from its web vault URL as `remoteRef.key`.

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: example
  namespace: default
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: bitwarden-login
  target:
    name: example
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: 00000000-0000-0000-0000-000000000000
        property: username
    - secretKey: password
      remoteRef:
        key: 00000000-0000-0000-0000-000000000000
        property: password
```

Available stores are:

- `bitwarden-login` for login `username` and `password`
- `bitwarden-fields` for named custom fields
- `bitwarden-notes` for the item's notes
- `bitwarden-attachments` for an attachment name or ID
- `bitwarden-ssh` for `privateKey`, `publicKey`, or `keyFingerprint`

## Verify the provider

```bash
kubectl -n external-secrets rollout status deployment/bitwarden-cli
kubectl get clustersecretstores.external-secrets.io
kubectl -n external-secrets logs deployment/bitwarden-cli
```

Do not expose the `bitwarden-cli` Service through an Ingress. Its HTTP API has
no authentication; the NetworkPolicy permits only the ESO controller to query
it.

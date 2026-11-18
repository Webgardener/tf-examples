
## Context

Deploying the Grafana dashboards ConfigMap fails with:

```
metadata.annotations: Too long: must have at most 262144 bytes
```

With a regular (client-side) `kubectl apply`, kubectl stores a full copy of the applied manifest in the `kubectl.kubernetes.io/last-applied-configuration` annotation, so it can compute the diff on the next apply. The dashboards' JSON push this annotation past the 256 KiB size limit for annotations.

## Solution

Switch to **Server-Side Apply (SSA)**. The diff and merge are then computed by the API server, which tracks field ownership in `metadata.managedFields`. That field stores only the **paths** of the fields, not their values. The `last-applied-configuration` annotation is no longer written on new objects, so the ConfigMap's size no longer hits this limit.

## New kubectl flags

| Flag | Meaning |
|---|---|
| `--server-side` | Enables Server-Side Apply: the API server computes the merge instead of kubectl, and field ownership is recorded in `metadata.managedFields` instead of the `last-applied-configuration` annotation. |
| `--force-conflicts` | When a field in our manifest is currently owned by another field manager (e.g. modified via `kubectl edit`, `kubectl scale`, or a controller), SSA rejects the apply with a conflict by default. This flag makes our apply take ownership and overwrite the value, which matches the previous client-side apply behavior. |
| `--field-manager=deploy-pipeline` | Name under which this deployment is recorded as the owner of the fields in `managedFields` (default: `kubectl`). A fixed, explicit name makes ownership readable and avoids conflicts between deployers. **The same name must be used everywhere these manifests are applied.** |

## Changes

- **Local (Skaffold)**: added `--server-side --force-conflicts` to `deploy.kubectl.flags.apply` in `skaffold.yaml`
- **Staging / Prod**: added `--server-side --force-conflicts --field-manager=deploy-pipeline` to the `kubectl apply` call in the deployment script

## Deployment steps

> ⚠️ If an object already carries the `last-applied-configuration` annotation, SSA keeps updating it (to allow downgrading back to client-side apply), so the error persists. The annotation must be removed **once per environment** before the first deployment.

### Local
1. Remove the annotation from the ConfigMap if it exists:
   ```bash
   kubectl annotate cm <dashboards-cm-name> -n <ns> kubectl.kubernetes.io/last-applied-configuration-
   ```
2. `skaffold run` / `skaffold dev`

### Staging
1. Check the impact without applying anything (expected: empty or minimal diff):
   ```bash
   kubectl diff --server-side --force-conflicts -f rendered/
   kubectl apply --server-side --dry-run=server -f rendered/
   ```
2. Remove the annotation from the dashboards ConfigMap:
   ```bash
   kubectl annotate cm <dashboards-cm-name> -n <ns> kubectl.kubernetes.io/last-applied-configuration-
   ```
3. Run the deployment script
4. Check that the annotation is gone:
   ```bash
   kubectl get cm <dashboards-cm-name> -n <ns> -o jsonpath='{.metadata.annotations}'
   ```
5. Check that the dashboards show up in Grafana

### Prod
Same steps as staging, once staging is validated.

## Points of attention

- **No more manual `kubectl apply` without `--server-side`** on these manifests: it would recreate the annotation, and the next deployment would fail again.
- **Conflicts**: `--force-conflicts` overwrites fields changed outside the pipeline (`kubectl edit`, `scale`…), just as client-side apply already did.
- **HPA**: if a Deployment managed by an HPA declares `replicas`, that field is overwritten on every deployment. The behavior is unchanged, but `replicas` should eventually be removed from those manifests.
- **Other objects** keep their existing `last-applied-configuration` annotation. This has no impact and needs no action.

## Rollback

Revert this MR: all objects go back to client-side apply. The dashboards ConfigMap will then fail again with the original error.

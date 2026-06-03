# DC1.Azure — EE Versioning & Deliberate Updates

How the DC1.Azure execution environment is versioned, and the exact loop to
ship a new build. Introduced in **AB#95**.

## Why this model

The Controller EE used to point at the floating `:latest` tag with
**`pull: always`**. Because `:latest` is mutable, a cached copy could go stale
after a rebuild (AB#91, found live — nodes kept running the old image), so the
workaround was to re-pull the whole ~521 MB image on **every** job run. That is
slow and once queued a concurrent job mid-demo.

The fix is **immutable tags + deliberate promotion**:

- Every image gets an **immutable semver tag** `vMAJOR.MINOR.PATCH`. A given tag
  never changes, so a cached copy is never stale.
- The Controller EE pins to that tag and uses **`pull: missing`** — pull once,
  then reuse the cached layer forever.
- An update never happens by surprise. You build a new tag, sync it, and
  **deliberately** bump the pin.

The floating `:latest` tag is still pushed to quay and synced to Hub, but only
as a Hub-less **smoke-test convenience** (`DC1_AZURE_EE_IMAGE=…:latest`).
Controller never references it.

## The version bump rule

| Change in the rebuild | Bump | Example |
|---|---|---|
| CVE-only security rebuild (errata, no source change) | **patch** | `v1.0.0 → v1.0.1` |
| Add or upgrade a collection / Python dep | **minor** | `v1.0.1 → v1.1.0` |
| New base image, ansible-core bump, or any breaking change | **major** | `v1.1.0 → v2.0.0` |

`v1.0.0` is the **2026-06-01 hardened baseline** (quay digest `sha256:4423a10…`),
minted from the existing digest with `skopeo copy` — no rebuild.

## Where the pin lives

| File | Field | Role |
|---|---|---|
| `aap_config/group_vars/all.yml` | `ee_version` | the single source of truth for the tag (default `v1.0.0`; override `DC1_AZURE_EE_VERSION`) |
| `aap_config/group_vars/all.yml` | `ee_image` | composes `<hub>/dc1_azure_ee:{{ ee_version }}` |
| `aap_config/files/hub_ee_repositories.yml` | `include_tags` | `[latest, "{{ ee_version }}"]` — PAH mirrors the pinned tag |
| `aap_config/files/controller_execution_environments.yml` | `pull: missing` | pull once, reuse cache |

Bumping **`ee_version`** alone cascades to the image ref and the Hub sync list.

## Shipping a new version — the loop

```bash
# 1. Build (only when image CONTENT changes — a re-tag of an existing digest skips this)
ansible-builder build -f execution-environment.yml -t dc1-azure-ee:latest --prune-images

# 2. Tag the next immutable version + move latest, then push both
NEXT=v1.0.1   # per the bump rule above
podman tag dc1-azure-ee:latest quay.io/zigfreed/dc1-azure-ee:$NEXT
podman tag dc1-azure-ee:latest quay.io/zigfreed/dc1-azure-ee:latest
podman push quay.io/zigfreed/dc1-azure-ee:$NEXT
podman push quay.io/zigfreed/dc1-azure-ee:latest

#   (Re-tagging an EXISTING digest without a rebuild — e.g. minting v1.0.0 — is a
#    server-side copy, no 2 GB push:)
#    skopeo copy docker://quay.io/zigfreed/dc1-azure-ee@sha256:<digest> \
#                docker://quay.io/zigfreed/dc1-azure-ee:$NEXT

# 3. Bump the pin + record provenance
#    - aap_config/group_vars/all.yml         → ee_version: "v1.0.1"
#    - execution-environment.yml             → add a BUILD PROVENANCE entry (what + why)
#    - CHANGELOG.md                          → Changed entry

# 4. Re-apply CaC (skip the running EDA activation — see the running-activation gotcha)
source docs/dev-environment.sh && \
ansible-playbook -i aap_config/inventory/ aap_config/load.yml --skip-tags rulebook_activation
```

On step 4 the PAH sync pulls the new tag into Hub, and Controller — seeing a tag
it doesn't have cached — pulls it **once** (`pull: missing`). Subsequent job runs
reuse the cache with no pull.

> **Robot account:** pushes use the quay robot `zigfreed+thinkpadp1gen3_cli`,
> which must hold **ADMIN** (write) on the repo — read-only returns 401 on push.
> See the `quay-io-namespace` note. The `zigfreed` personal account can't mint an
> OAuth token, so there is no API automation for tags — they're pushed by hand.

## Verifying a promotion

```bash
# Controller EE now references the pinned tag with pull: missing
curl -sk -u "$AAP_CONTROLLER_USERNAME:$AAP_CONTROLLER_PASSWORD" \
  "$AAP_HOSTNAME/api/controller/v2/execution_environments/?name=DC1.Azure%20-%20EE" \
  | python3 -c "import sys,json;e=json.load(sys.stdin)['results'][0];print(e['image'], e['pull'])"
# → …/dc1_azure_ee:v1.0.1 missing

# Then run any DC1.Azure JT and confirm it succeeds on the new tag.
```

## References

- `execution-environment.yml` — the EE definition + BUILD PROVENANCE log
- `docs/ee-security-remediation.md` — the hardening story behind `v1.0.0`
- `aap_config/files/hub_ee_repositories.yml` — the two-gate PAH sync rule

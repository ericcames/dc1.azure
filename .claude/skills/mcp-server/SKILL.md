---
name: mcp-server
description: >-
  Deploy and configure the AAP MCP server so AI coding assistants (Claude Code,
  Cursor) can query and control AAP via the Model Context Protocol. TRIGGER when
  the user mentions "MCP server", "MCP setup", "connect Claude to AAP", "agentic
  AI", "Model Context Protocol", or wants AI agents to interact with a live AAP
  instance. SKIP for normal AAP config (use /install-dc1-azure), code-only
  changes, or if the user only wants to inspect MCP docs without deploying.
---

# Deploy AAP MCP Server

Set up the AAP Model Context Protocol server so AI agents can query inventories,
launch jobs, monitor status, and manage the platform — all governed by AAP RBAC.
The MCP server requires **AAP 2.7+** (operator v2.7.0+).

## Guardrails

- **Never print tokens or OCP passwords.** Check env vars by name only. When a
  secret is missing, ask the user to type `! export NAME=...` in the prompt.
- **MCP token** goes in `docs/dev-environment.sh` (gitignored), never committed.
- **`.mcp.json`** is gitignored — it contains the bearer token header.
- **All OCP commands need an active `oc login`** session.
- **Shell state does not persist** across Bash tool calls — bundle `source` +
  commands in a single invocation.

## Steps

### 1. Verify AAP version

```bash
oc get csv -n aap 2>/dev/null | grep aap-operator
```

The operator must be **v2.7.0+**. AAP 2.6 has the MCP CRD field but the
operator playbook cannot deploy it — reconciliation fails at "Register HTTP
Ports".

If on 2.6, upgrade first:

```bash
# Check available channels
oc get packagemanifest ansible-automation-platform-operator \
  -o jsonpath='{range .status.channels[*]}{.name}{"\t"}{.currentCSV}{"\n"}{end}'

# Switch to stable-2.7
oc patch subscription ansible-automation-platform-operator -n aap \
  --type merge -p '{"spec":{"channel":"stable-2.7"}}'

# Wait for install plan, then approve
oc get installplan -n aap  # find the new pending one
oc patch installplan <NAME> -n aap --type merge -p '{"spec":{"approved":true}}'
```

**Warning:** upgrading restarts AAP pods — brief downtime expected. On
single-node RHDP clusters, disk pressure may occur during image pulls; wait
for kubelet GC to clear it.

**Post-upgrade gotcha — EDA Redis ACL mismatch:** the 2.7 Redis instance may
not have the `eda` ACL user that the EDA Redis secret references. Fix:

```bash
# Check
oc exec aap-redis-0 -n aap -- redis-cli -u redis://default:<REDIS_PASS>@localhost:6379 ACL LIST

# If no 'eda' user, update the secret
oc patch secret aap-eda-redis-configuration -n aap \
  --type merge -p '{"stringData":{"username":"default"}}'

# Then restart all EDA pods
oc delete pods -n aap -l app.kubernetes.io/part-of=aap-eda
```

### 2. Verify OCP access

```bash
oc whoami && oc project aap
```

If expired, the user needs to re-authenticate:
`! oc login <API_URL> -u kubeadmin -p <password> --insecure-skip-tls-verify`

### 3. Check if MCP is already deployed

```bash
oc get ansiblemcpserver -n aap
oc get pods -n aap | grep mcp
oc get routes -n aap | grep mcp
```

If the MCP pod is Running and the route exists, skip to **Step 6**.

### 4. Deploy MCP server

**Option A — via AAP CR** (preferred when operator reconciliation is clean):

```bash
oc patch aap/aap -n aap --type merge \
  -p '{"spec":{"mcp":{"disabled":false,"allow_write_operations":false}}}'
```

Wait ~2 minutes for reconciliation. Check status:

```bash
oc get aap/aap -n aap -o jsonpath='{.status.conditions}' | \
  python3 -c "import sys,json; [print(f'{c[\"type\"]}: {c[\"status\"]}') for c in json.load(sys.stdin)]"
```

If `Successful: True`, the MCP pod and route should exist. If reconciliation
fails (common: "Remove stale routes" error from 2.6→2.7 upgrades), use
Option B.

**Option B — direct CR creation** (bypasses operator reconciliation issues):

```bash
cat <<'EOF' | oc apply -n aap -f -
apiVersion: mcpserver.ansible.com/v1alpha1
kind: AnsibleMCPServer
metadata:
  name: aap-mcp
  namespace: aap
spec:
  allow_write_operations: false
  route_tls_termination_mechanism: Edge
  public_base_url: https://<AAP_HOSTNAME>
EOF
```

Replace `<AAP_HOSTNAME>` with the actual AAP gateway URL from
`docs/dev-environment.sh`.

### 5. Verify MCP server is running

```bash
MCP_ROUTE=$(oc get route aap-mcp -n aap -o jsonpath='{.spec.host}')
echo "MCP Route: https://${MCP_ROUTE}"
curl -sk "https://${MCP_ROUTE}/"
```

Should return the list of MCP tool endpoints:
`/mcp/job_management`, `/mcp/inventory_management`,
`/mcp/system_monitoring`, `/mcp/user_management`,
`/mcp/security_compliance`, `/mcp/platform_configuration`, and `/mcp` (all).

### 6. Create AAP token for MCP

Create a gateway personal access token with **read** scope:

```bash
source docs/dev-environment.sh && \
curl -sk -u "${AAP_CONTROLLER_USERNAME}:${AAP_CONTROLLER_PASSWORD}" \
  -X POST "${AAP_HOSTNAME}/api/gateway/v1/tokens/" \
  -H "Content-Type: application/json" \
  -d '{"description":"MCP Server - Claude Code","scope":"read"}'
```

Save the returned token value. Add to `docs/dev-environment.sh`:

```bash
export AAP_MCP_URL=https://<MCP_ROUTE>/mcp
export AAP_MCP_TOKEN=<TOKEN_VALUE>
```

For write operations (launching jobs via MCP), create a token with `write`
scope and set `allow_write_operations: true` on the MCP CR. **Note:** changing
permissions requires deleting and recreating the `AnsibleMCPServer` CR.

### 7. Configure Claude Code

```bash
source docs/dev-environment.sh && \
claude mcp add --transport http ansible-aap "${AAP_MCP_URL}" \
  --header "Authorization: Bearer ${AAP_MCP_TOKEN}" --scope project
```

This creates `.mcp.json` in the repo root. Verify it is gitignored:

```bash
grep -q '.mcp.json' .gitignore && echo "OK: gitignored" || echo "MISSING: add .mcp.json to .gitignore"
```

### 8. Verify in Claude Code

Start a new Claude Code session (the MCP server loads at session start).
Run `/mcp` to confirm `ansible-aap` is connected, then test:

> "What job templates are available on AAP?"

### 9. Configure Cursor (optional)

If using Cursor, add the MCP server via Settings → MCP Servers using the same
URL and bearer token from `docs/dev-environment.sh`.

## On failure

| Symptom | Cause | Fix |
|---------|-------|-----|
| Operator v2.6 fails at "Register HTTP Ports" | MCP not supported in 2.6 operator | Upgrade to 2.7 (Step 1) |
| `Successful: False` after patching CR | Stale routes from 2.6 | Delete `aap-controller`/`aap-eda` routes, or use Option B |
| EDA pods CrashLoopBackOff after upgrade | Redis ACL mismatch | Set EDA Redis username to `default` (Step 1 post-upgrade) |
| Disk pressure blocks pod scheduling | RHDP single-node cluster disk full | Wait for kubelet GC, or delete completed/errored pods |
| MCP returns 401 | Token expired or wrong scope | Create a new gateway token (Step 6) |
| `/mcp` shows no server in Claude Code | Session started before `.mcp.json` | Restart Claude Code session |

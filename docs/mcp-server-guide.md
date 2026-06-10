# AAP MCP Server — Why It Matters and How to Get Started

## The 30-second version

AI coding assistants can now talk directly to Ansible Automation Platform.
They can ask what's running, check if a job failed, browse inventories, and
even launch automation — all through the same RBAC and approval gates your
team already uses. No new permissions model to learn. No shadow IT. The AI
gets the same access as the person using it, and every action is auditable.

This is the **Model Context Protocol (MCP)** server, shipped with AAP 2.7.

---

## Why would I set this up?

### 1. AI without guardrails is dangerous — MCP adds the guardrails

Every customer conversation about AI eventually hits the same question:
*"How do I let AI do useful things without giving it the keys to production?"*

MCP + AAP answers this cleanly. The AI agent connects to AAP through the
same gateway API that humans use. It authenticates with a personal access
token scoped to a specific user. That user's RBAC permissions determine what
the AI can see and do. If the user can't launch a workflow, neither can the
AI. If the user can only see one organization's inventories, the AI sees
the same thing.

No special AI permissions. No separate governance model. The platform you
already manage is the platform that governs the AI.

### 2. Context switching kills productivity

Platform engineers bounce between the AAP UI, a terminal, ServiceNow,
Dynatrace, and half a dozen browser tabs. Every switch breaks focus.

MCP lets an AI agent pull data from AAP right where you're already working.
In Claude Code or Cursor, you can ask "show me the last 5 failed jobs"
without opening a browser. The AI queries AAP, formats the answer, and you
stay in your flow.

This isn't a chatbot bolted onto a dashboard. It's your automation platform
speaking the same protocol as your coding tools.

### 3. Automation should be composable — MCP is an open standard

MCP is not a Red Hat proprietary API. It's an open standard supported by
Anthropic (Claude), OpenAI, Cursor, VS Code extensions, and a growing
ecosystem of AI tools. The same AAP MCP server works with any
MCP-compatible client.

Today you connect Claude Code. Tomorrow you connect a different AI tool.
Your AAP configuration doesn't change. No vendor lock-in on the AI side.

---

## What can you actually do with it?

### Customer demo scenarios

These are things you can show a customer to demonstrate AAP's role in the
agentic AI story.

**"Ask your platform"** — Connect an AI coding assistant to AAP via MCP.
Ask it "What job templates are available?" or "Which hosts are in the
production inventory?" The AI returns live data from your actual platform,
not a slide deck. Customers see that AAP is queryable by AI agents out of
the box.

**AI-assisted troubleshooting** — Ask the AI "What jobs failed in the last
24 hours? Show me the logs." It queries AAP, finds the failed job, reads
the output, and suggests a fix — all in the terminal. This is the "Day 2
operations" story: AI doesn't replace the operator, it accelerates the
investigation.

**Governed AI execution** — With write mode enabled, ask the AI to "Launch
the provisioning workflow for a small Windows VM." The AI translates your
intent into an API call. AAP enforces RBAC and survey validation. If your
token doesn't have Execute permission, the request fails gracefully —
and that's the point. Governance works the same whether the request comes
from a human clicking a button or an AI agent calling the API.

**Closed-loop incident response** — Combine MCP with Event-Driven Ansible:
Dynatrace detects a problem, EDA triggers a remediation workflow, the AI
agent monitors the workflow via MCP, and confirms resolution back to
ServiceNow. Full loop, no human in the critical path, complete audit trail.
This is the "autonomous operations" vision — with AAP as the trust layer.

### SE productivity use cases

These are ways you can use MCP in your own daily work to move faster.

**Check job status without leaving the terminal** — "Did the last load.yml
run succeed? What was the result?" Get the answer while you're still coding
instead of switching to the AAP browser tab.

**Inventory queries** — "What hosts are in the dc1-azure inventory? Are
any showing as unreachable?" Faster than navigating three clicks in the UI.

**Quick credential audit** — "List all credentials with 'DC1.Azure' in the
name." Verify your Config-as-Code applied correctly without hunting through
the AAP UI.

**Build, deploy, and verify in one session** — Edit a playbook, run
`load.yml`, then ask the MCP "Is the new job template there? What does its
survey look like?" All without switching windows. Your AI assistant becomes
your verification step.

---

## How it works

MCP (Model Context Protocol) is an open standard that lets AI tools talk to
external services through a structured API. AAP 2.7 ships an MCP server that
exposes six tool categories:

| Category | What it covers |
|----------|---------------|
| Job management | List templates, launch jobs, monitor status |
| Inventory management | Query hosts, groups, variables |
| System monitoring | Retrieve logs, check platform health |
| User management | Inspect access, teams, organizations |
| Security & compliance | Audit credentials, verify platform integrity |
| Platform configuration | Review settings, inspect infrastructure |

Every request goes through the AAP gateway, authenticated with a personal
access token and subject to the same RBAC rules as the web UI. The MCP
server supports **read-only mode** (safe for exploration) and **read-write
mode** (for executing automation).

---

## Getting started

### 1. Deploy the MCP server

Run the `/mcp-server` skill in Claude Code — it walks through prerequisites,
deploys the server, creates a token, and wires up the connection. Total time:
15–30 minutes on a working AAP 2.7 instance.

See [`.claude/skills/mcp-server/SKILL.md`](../.claude/skills/mcp-server/SKILL.md)
for the full step-by-step.

### 2. Try read-only first

Start with safe queries to build confidence:

- "What inventories exist on AAP?"
- "Show me the job templates with 'DC1.Azure' in the name."
- "What was the last job that ran? Did it succeed?"
- "Which hosts are in the dc1-azure-control inventory?"

These use the default read-only token scope. Nothing changes on the platform.

### 3. Graduate to write mode

When you're ready to let the AI execute automation:

1. Edit the `AnsibleMCPServer` CR: set `allow_write_operations: true`
   (requires deleting and recreating the CR — see the skill for details)
2. Create a new gateway token with **write** scope
3. Update `docs/dev-environment.sh` and `.mcp.json` with the new token

Start with low-risk operations: "Launch the url_checker job template" or
"Sync the DC1.Azure project." Build trust incrementally.

---

## Red Hat's positioning

Red Hat frames AAP as the **trusted execution layer for agentic AI**. The
message: AI agents can reason, plan, and recommend — but when it's time to
actually change infrastructure, that action goes through AAP. RBAC gates it.
Approval workflows validate it. The audit trail records it.

The MCP server is how that story becomes real. It's the bridge between "AI
is cool in a demo" and "AI we can deploy in production with governance."

For more on Red Hat's agentic AI strategy, see the
[AAP 2.7 MCP server announcement](https://www.redhat.com/en/blog/it-automation-agentic-ai-introducing-mcp-server-red-hat-ansible-automation-platform).

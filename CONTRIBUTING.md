# Contributing

## Workflow

**Every change follows this sequence — no exceptions:**

```
Open work item → branch from main → implement → open PR (AB#N) → merge → work item resolves
```

1. **Open an ADO Boards work item first** — before writing a single line of code, create a User Story or Task under the appropriate phase Epic in the `dc1.azure` ADO project. Describe what you're changing and why. No implementation without a work item.
2. **Branch from `main`** — use the naming pattern `<type>/<short-description>` (e.g. `fix/winrm-bootstrap`, `feat/storage-backend`, `docs/roadmap-update`).
3. **One concern per PR** — group changes by shared root cause, not item count. The test: would you revert these together? If yes, ship them together. Behavior changes stay isolated regardless.
4. **Reference the work item** — include `AB#<id>` in your PR description so the work item autolinks in ADO. The PR template at [`.azuredevops/pull_request_template.md`](.azuredevops/pull_request_template.md) has a dedicated `AB#` field — fill it in. Set the work item state to *Resolved* in the PR side-panel so it closes on merge.
5. **PRs target `main`** — direct pushes to `main` are blocked by branch policy (enforced in Phase 0.5). Every change goes through a PR, which also exercises the ADO Pipeline lint/validate checks before merge.
6. **Update CHANGELOG.md** — every PR must include a CHANGELOG entry grouped under Added / Changed / Fixed / Removed.

### `AB#<id>` autolink syntax

`AB#123` (no slash, case-sensitive on the `AB`) is ADO's built-in autolink syntax. Anywhere ADO renders Markdown — PR descriptions, PR comments, commit messages, work-item discussions — `AB#123` becomes a clickable link to work item 123 in this project. Use it consistently so any reviewer can trace a change back to its work item with one click. See [`docs/ado-conventions.md`](docs/ado-conventions.md) for the full ADO operating model.

## Branch naming

| Prefix | When to use |
|--------|-------------|
| `feat/` | New capability, role, or playbook |
| `fix/` | Bug fix |
| `docs/` | Documentation only |
| `chore/` | Dependency updates, CI, housekeeping |
| `refactor/` | Code restructure with no behavior change |

## Commit messages

```
<type>: <short description>

<optional body explaining why, not what>

AB#<work-item-id>
```

Types: `feat`, `fix`, `docs`, `refactor`, `chore`

## Code conventions

See [CLAUDE.md](CLAUDE.md) for full detail. Key rules:

- **No project-local `ansible.cfg`** — use the user's `~/.ansible/ansible.cfg` and pass options via CLI flags or env vars
- **`ansible.platform` over `ansible.controller`** — `ansible.controller` is legacy; never use it in new code
- **Always delete tokens** — any playbook that creates an AAP token must delete it in an `always:` block
- **Namespace AAP objects with `DC1.Azure -` prefix** — coexists with `demo.datacenter` AWS objects in shared AAP instances
- **Layer order matters** — Terraform (Layer 0) must be solid before AAP CaC (Layer 1); AAP CaC before workflow + roles (Layer 2). Don't build on an unstable foundation.

## Testing

- **Terraform changes** — `terraform fmt -check`, `terraform validate`, and at minimum `terraform plan` against a real RHDP env. `apply` + `destroy` where feasible. Document what you ran in the PR description.
- **Ansible role / playbook changes** — test against a real AAP job template run. Document the JT name and outcome in the PR description.
- **ADO Pipeline** — `azure-pipelines.yml` runs `yamllint`, `ansible-lint`, `terraform fmt -check`, `terraform validate` on every PR. Locally: install [`pre-commit`](https://pre-commit.com/) and the same hooks to catch issues before pushing.

## Sensitive data

Never commit:

- Credentials, tokens, or passwords of any kind
- `docs/dev-environment.sh` — your env file with AAP / Azure / ADO secrets (copy from `docs/dev-environment.sh.example`)
- Terraform state files (`*.tfstate*`) — state lives in Azure Storage
- `terraform.tfvars` (real values) — only `terraform.tfvars.example` is committed

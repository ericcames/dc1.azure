## Summary

<!--
1-3 sentences. What this PR changes and the user-visible outcome.
Focus on "why," not "what" — the diff already shows what.
-->


## Work item

<!--
ADO autolink: write the work-item ID inline as "AB#123" (no slash) and
ADO will render it as a clickable link to the work item. The PR side-panel
also has a "Linked work items" picker — use it AND drop AB#<id> here so
the linkage shows up in the commit message after squash-merge.

Set the work item State to *Resolved* in the side-panel so it auto-closes
when this PR merges to main.

See docs/ado-conventions.md for the Boards Epic→Feature→Story hierarchy
this work item should live under.
-->

AB#


## Test plan

<!--
Markdown checklist of what was tested. Be specific — names of JTs run,
`terraform plan` outputs reviewed, files manually inspected.

Minimums by area:
  - Terraform: `terraform fmt -check` + `terraform validate`; ideally
    `terraform plan` against a real RHDP env.
  - Ansible playbooks: `ansible-playbook --syntax-check`; ideally a
    live JT run with the outcome noted here.
  - AAP CaC (aap_config/): a successful `aap_config/load.yml` run + API
    verification that every named object exists.
  - Docs / config only: "n/a — docs only" is acceptable.
-->

- [ ]
- [ ]


## Risk / rollback

<!--
What is the blast radius if this is wrong?
How would we revert? (Default: `git revert <sha>`. Call out anything
that wouldn't cleanly revert — DB migrations, infra state, AAP-side
deletions, branch-policy changes.)

Anything touching shared AAP, Azure infrastructure, or branch policies
needs explicit risk + rollback notes here.
-->


---

### Checklist (see CONTRIBUTING.md)

- [ ] Work item linked above (`AB#<id>` autolink) and State set to *Resolved*
- [ ] One concern per PR (would you revert these changes together?)
- [ ] `CHANGELOG.md` updated under Added / Changed / Fixed / Removed
- [ ] No secrets, `*.tfstate*`, real `terraform.tfvars`, or `docs/dev-environment.md` committed

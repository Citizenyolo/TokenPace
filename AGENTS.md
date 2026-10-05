# TokenPace agent guide

Guidance revision: 2026-10-05 / v1. Derived from the team's approved Ways of
Working (WOW), synchronized by Codex. This is the repository's maintained
application of that charter, not an independently maintained team charter.

## Start here

Read this file and the current task brief before proposing a plan. Read
[README.md](README.md) for architecture and known issues, and
[CONTRIBUTING.md](CONTRIBUTING.md) for contribution steps. Briefly confirm the
guidance revision, relevant roles, task boundaries and any capability conflict.
For this repository, use this guide as the source of approved operating rules;
Jules Memories are supplementary context. If a memory conflicts with current
instructions, flag it rather than treating it as authority. Neither this file
nor a memory grants permission to execute, publish, merge or deploy.

The task brief supplies the current goal, base branch, scope, acceptance evidence
and action permissions. Recover current status from source, issues and the
coordinator's handoff; do not infer completion from an old suggestion or session.

## Roles and collaboration

- Zoli is the Client: goals, priorities and consequential decisions.
- Codex coordinates, reviews completed candidates and handles routine gates
  within the task's authority. Codex performs the final merge after consulting
  Zoli and receiving approval for the reviewed PR/head.
- Jules is the default cloud developer: implementation, self-checks, revisions
  and authorized PR publication. AGY handles delegated local macOS development
  and integration. A cloud session cannot access the coordinator's Mac files.
- Speak concise Hungarian to Zoli; English is acceptable between agents.
  Every message addressed to Jules starts with literal `@Jules` followed by
  whitespace or end of text. The sender validates it and reads back the posted
  body independently. Codex messages to AGY start with `Codex → AGY`.

One owner per deliverable. Propose proportionate stages and review gates, then
work autonomously within a stage. Present a completed, self-checked candidate
with evidence at the gate; Codex returns consolidated feedback. Escalate a
material blocker, concrete risk or scope/authority conflict early. Avoid
overlapping audits, repeated finished checks and piecemeal interim reviews.

## Repository and validation

TokenPace is a Swift macOS application plus WidgetKit extension. `project.yml`
defines both targets; source lives under `Sources/TokenPace`,
`Sources/TokenPaceExtension` and `Sources/Shared`. Quota retrieval invokes the
locally authenticated Agy CLI; application runtime checks can therefore contact
upstream through that CLI.

- On an authorized macOS development checkout, `xcodegen generate` generates
  the project. A build-only command is
  `xcodebuild -project TokenPace.xcodeproj -scheme TokenPace -derivedDataPath /path/to/task-owned/DerivedData build`.
  Replace the example path with a task-owned directory and use the task's
  approved signing configuration. Do not run this on Linux.
- Jules runs on Ubuntu: macOS app/widget builds and runtime acceptance require
  an authorized local macOS checkpoint. Report that limitation rather than
  presenting shell checks as full application validation.
- For installer staging changes, run `bash -n install.sh` and
  `bash test_install_staging.sh` from the repository root. The harness extracts
  an isolated staging fixture; it does not build, sign, install or restart the
  application. Review changes to its isolation boundary before running it.
- `install.sh` builds, signs, replaces the installed app, registers the widget
  and restarts the daemon. It is an installation operation, not a general test
  command. Installation, restart, network acceptance and release require
  explicit task authority.
- Choose checks relevant to the change; report commands, results and remaining
  limits. Preserve unrelated dirty/untracked work and unpublished candidates.

## Branches and publication

Changes to `main` go through a PR. Do not force push, delete or routinely bypass
protection on `main`, including through admin privileges. Codex checks actual
GitHub protection at repository task start. Use a feature branch; Codex-created
branches use `codex/` by default. Do not rewrite others' branches without
specific authority.

Jules owns development and PR revisions; final merge belongs to Codex under
Zoli's specific approval. Task GO or plan approval is not merge/deploy approval.
Verify published results on GitHub and the fetched branch, not only a session's
completion flag. Preserve stronger existing rules. Required GitHub approvals
and CI checks are enabled only when a suitable working reviewer/test process
exists; never claim absent checks passed or silently relax protection.

## Keep guidance current

Codex updates this file through a documentation PR when approved shared rules
or repository facts change, records the source WOW revision in the private
handoff, and reconciles conflicting Memories. Keep this file concise and
public-safe: no credentials, private workstation paths or session history.
At the next real Jules task, verify that this revision was loaded and understood
before relying on a shortened onboarding brief. Automatic discovery is
documented by Jules; behavioral verification is still a checkpoint.

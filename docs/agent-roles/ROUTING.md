# Adaptive Task Routing

## Purpose

Choose the lightest workflow that safely satisfies the task.

Do not introduce Architect, Reviewer or QA ceremony when the task does not
justify it.

Do not skip architecture, review or QA when risk or ambiguity requires them.

At the beginning of a non-trivial task, identify the selected route briefly.

Example:

Route: Builder → Reviewer

Do not produce a long routing explanation unless requested.

---

# Route 1 — Read-only Investigation

Use when the user asks to:

- understand existing behaviour;
- troubleshoot;
- inspect metadata;
- inspect Salesforce data/configuration;
- compare repository and org;
- explain how something currently works.

Default role:

READ-ONLY INVESTIGATOR

Rules:

- inspect first;
- do not modify files or Salesforce;
- identify whether the problem is data, configuration, permissions,
  scheduling, optimization, mobile cache, offline priming, sync,
  automation, code, integration or performance;
- recommend next action after evidence is gathered.

Escalate to Architect if the investigation exposes an architectural decision.

Escalate to Builder only after the required change is sufficiently defined.

---

# Route 2 — Direct Builder

Use for small, explicit, low-risk implementation tasks.

Examples:

- change an existing label;
- add a clearly defined field to an existing component;
- make a small Flow adjustment with known behaviour;
- update an existing query;
- make a narrowly scoped Apex change with an unambiguous requirement;
- update documentation or metadata without architectural impact.

Workflow:

Builder

Builder must:

1. inspect;
2. state the minimal intended change;
3. implement;
4. add/update automated tests where applicable;
5. validate;
6. show the complete diff.

Reviewer is optional unless risk is discovered.

QA is optional unless runtime behaviour requires independent validation.

Architect is not required.

---

# Route 3 — Builder → Reviewer

Use for implementation that is defined but technically meaningful.

Typical triggers:

- Apex changes;
- Flow logic changes;
- LWC changes;
- integration logic;
- shared utility code;
- permissions/security;
- inventory processing;
- scheduling behaviour;
- transaction boundaries;
- retry/idempotency;
- multiple metadata components;
- meaningful regression risk.

Workflow:

Builder
→ REVIEWER HANDOFF
→ Reviewer

Builder owns automated tests.

Reviewer independently validates implementation and architecture compliance.

QA is added when runtime behaviour, personas, mobile/offline or end-to-end
behaviour must be demonstrated.

---

# Route 4 — Architect → Builder → Reviewer

Use when implementation requires a technical design decision before coding.

Typical triggers:

- data-model choice;
- Work Order / WOLI / Service Appointment modelling;
- integration contract design;
- scheduling architecture;
- security model;
- inventory ownership model;
- Entitlement / SLA design;
- cross-domain changes;
- multiple viable technical approaches;
- non-trivial trade-offs.

Workflow:

Architect
→ BUILDER HANDOFF
→ Builder
→ REVIEWER HANDOFF
→ Reviewer

If Architect identifies unresolved business or architectural decisions:

STOP.

Do not continue to Builder until the required human decision is provided.

---

# Route 5 — Architect → Builder → Reviewer → QA

Use for high-risk or behaviourally significant changes.

Typical triggers:

- technician-facing Field Service functionality;
- Field Service Mobile;
- offline behaviour;
- lifecycle changes;
- scheduling behaviour;
- inventory movement;
- security/persona changes;
- integration end-to-end behaviour;
- retry/idempotency;
- data migration;
- multiple systems;
- business-critical automation;
- changes with substantial regression risk.

Workflow:

Architect
→ BUILDER HANDOFF
→ Builder
→ REVIEWER HANDOFF
→ Reviewer
→ QA HANDOFF
→ QA
→ User approval

QA must independently execute the applicable acceptance scenarios.

Technical review does not replace QA.

---

# Route 6 — Human Decision Required

Use whenever implementation depends on unresolved:

- business behaviour;
- architectural decision;
- source-of-truth ownership;
- lifecycle semantics;
- security ownership;
- integration contract;
- licensing;
- contractual SLA rule;
- scope decision.

Workflow:

Architect
→ Human decision
→ appropriate implementation route

Do not invent a decision to continue implementation.

---

# Risk Escalation

A task must move to a stronger route when any of these appear:

- architecture ambiguity;
- destructive operation;
- Production impact;
- security impact;
- integration contract change;
- mobile/offline impact;
- data migration;
- concurrency;
- idempotency;
- cross-object lifecycle;
- shared framework/component;
- unclear source of truth;
- large data volume;
- user-visible regression risk.

A task may move to a lighter route when analysis proves those risks do not apply.

---

# Salesforce-Specific Routing

## Apex

Small explicit Apex fix:

Builder → Reviewer

Material Apex implementation:

Builder → Reviewer

Architect first when Apex is being introduced to solve an unresolved design
problem or when multiple architecture options exist.

Builder owns Apex test classes.

QA validates runtime behaviour where applicable.

---

## Flow

Small explicit Flow change:

Builder

Use Builder → Reviewer when:

- transaction behaviour changes;
- record lifecycle changes;
- multiple records are updated;
- failure handling matters;
- the Flow is shared or business-critical.

Use Architect first when the Flow implements an unresolved business lifecycle.

FieldServiceMobile Flow changes normally require QA when technician behaviour
or offline execution is affected.

---

## LWC

Simple presentation-only change:

Builder

Business logic or data-access change:

Builder → Reviewer

Field Service Mobile / offline LWC:

Architect → Builder → Reviewer → QA

unless the architecture and behaviour are already explicitly approved.

---

## Integrations

Minor mapping correction with approved contract:

Builder → Reviewer

New endpoint, contract, ownership, retry or reconciliation model:

Architect → Builder → Reviewer → QA

---

## Security

Minor permission correction with approved security model:

Builder → Reviewer

New sharing/persona/security model:

Architect → Builder → Reviewer → QA

---

# Worktree Guidance

Use the local project by default for:

- read-only work;
- small explicit tasks;
- user-supervised changes.

Prefer an isolated worktree for:

- autonomous Builder work;
- non-trivial implementation;
- experiments;
- parallel agents;
- high-risk changes;
- Architect → Builder → Reviewer workflows.

The routing decision and worktree decision are related but independent.

Do not create a worktree merely for ceremony.

---

# Execution Environment Routing

The task route and the Git execution environment must be evaluated separately.

## Local Project

Use the local project for:

- read-only investigation;
- Architect work;
- Reviewer work;
- QA analysis that does not require implementation;
- small, explicit, low-risk Builder changes;
- user-supervised changes where immediate visibility in the main working tree is desired.

## Isolated Worktree

Prefer an isolated worktree for:

- non-trivial Builder implementation;
- autonomous implementation;
- changes affecting multiple components;
- Apex, Flow or LWC changes with meaningful regression risk;
- integration changes;
- security changes;
- lifecycle changes;
- inventory processing;
- mobile/offline implementation;
- experimental changes;
- parallel agent work;
- Architect → Builder → Reviewer workflows.

## Environment Escalation

If a task starts in the local project but routing determines that an isolated
worktree is appropriate:

STOP before modifying files.

State:

"Execution environment escalation: isolated worktree recommended."

Explain briefly why.

Do not create implementation changes in the local project merely because the
thread was started there.

The user can then start the Builder task in an isolated worktree using the
approved BUILDER HANDOFF.

## Environment De-escalation

Do not require a worktree for:

- read-only work;
- documentation-only analysis;
- trivial local changes;
- small explicit modifications with negligible regression risk.

Avoid worktrees when they add ceremony without meaningful isolation benefit.

---

# Routing Output

At the start of a non-trivial task state only:

Route: <selected route>

Example:

Route: Architect → Builder → Reviewer → QA

Then proceed with the selected role.

If the route changes because new information is discovered, state:

Route escalated: <new route>

and explain the reason briefly.

When implementation is involved, also state the execution environment when material.

Examples:

Route: Builder
Environment: Local project

Route: Architect → Builder → Reviewer
Environment: Architect local/read-only; Builder isolated worktree

Route: Reviewer → QA
Environment: Local project / read-only

Builder → Reviewer
Architect → Builder → Reviewer
Architect → Builder → Reviewer → QA
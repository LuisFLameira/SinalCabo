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

# Route 1 — Analyst

Use when the primary need is to investigate, understand, prove or disprove
behaviour before architecture or implementation.

Typical triggers:

- understand existing behaviour;
- troubleshoot;
- inspect Salesforce data/configuration;
- compare repository and org;
- determine whether Salesforce standard supports a requirement;
- validate a technical hypothesis;
- execute a focused PoC;
- reproduce behaviour using controlled sandbox data.

Workflow:

Analyst

Default mode is read-only investigation.

The Analyst may escalate to controlled PoC execution in SinalCabo_DEV according
to CONTROLLED_TEST_DATA.md when the request authorizes testing, validation,
reproduction or proof of behaviour.

Possible outcomes:

- ANALYSIS COMPLETE
- ARCHITECT HANDOFF
- BUILDER HANDOFF
- HUMAN DECISION REQUIRED

Escalate to Architect when evidence exposes a design decision.

Escalate to Builder only when behaviour and implementation direction are
sufficiently defined.

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

# Route 4 — Builder → Reviewer → QA

Use when the implementation behaviour is already explicitly approved but
independent runtime validation is required.

Typical triggers:

- Field Service Mobile change with approved behaviour;
- technician-facing Flow with approved lifecycle;
- approved security/persona implementation;
- approved inventory behaviour;
- runtime-sensitive Flow/Apex/LWC change;
- meaningful regression risk requiring functional validation;
- implementation requiring persona, mobile, offline or end-to-end evidence.

Workflow:

Builder
→ REVIEWER HANDOFF
→ Reviewer
→ QA HANDOFF
→ QA when executable
→ User acceptance

Architect is not required when:

- business behaviour is explicitly approved;
- architecture is already established;
- no unresolved design decision remains.

QA may be DEFERRED according to the QA Spawn Gate.

---

# Route 5 — Architect → Builder → Reviewer

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

# Route 6 — Architect → Builder → Reviewer → QA

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

# Route 7 — Human Decision Required

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

Use:
Builder → Reviewer → QA
when behaviour and architecture are already approved.

Use:
Architect → Builder → Reviewer → QA
only when an unresolved lifecycle, architecture or design decision remains.

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


## Subagent Orchestration

The main thread remains the orchestrator for delegated roles.

Use project custom subagents for:
- Analyst → `analyst`
- Reviewer → `reviewer`
- QA → `qa`

- the main thread remains the orchestrator;
- Reviewer should be delegated to the project `reviewer` subagent;
- QA should be delegated to the project `qa` subagent;
- Reviewer is independent and read-only;
- QA is independent from Builder and Reviewer;
- QA may create or modify controlled sandbox test data when authorized under
  CONTROLLED_TEST_DATA.md;
- QA must not modify implementation metadata or source code;
- the main thread waits for each result before continuing.

Execution sequence for:

Architect → Builder → Reviewer → QA

is:

1. Architect produces BUILDER HANDOFF.
2. Builder implements.
3. Main thread spawns reviewer.
4. Reviewer returns REVIEW OUTCOME + QA HANDOFF.
5. If review passes, main thread spawns QA.
6. QA returns QA OUTCOME.
7. Main thread presents the consolidated result to the user.

Do not skip directly from Builder to QA.
Do not run QA after a blocking Reviewer result.

### Analyst Delegation

When the selected route starts with Analyst:

- the main thread remains the orchestrator;
- delegate the investigation to the project `analyst` subagent;
- provide:
  - the user question or requirement;
  - relevant known context;
  - any explicit constraints;
  - whether controlled PoC execution is implied by the request;
- wait for the ANALYSIS RESULT.

After Analyst returns:

- ANALYSIS COMPLETE → present the result and stop;
- ARCHITECT HANDOFF → continue with Architect;
- BUILDER HANDOFF → continue with the appropriate Builder route;
- HUMAN DECISION REQUIRED → stop and request the decision.

Do not make the parent thread repeat the Analyst investigation.

The Analyst subagent may create or modify controlled test data in
SinalCabo_DEV only according to CONTROLLED_TEST_DATA.md.

---

## QA Spawn Gate

Before spawning the `qa` subagent, the parent must answer:

QA REQUIRED?
QA EXECUTABLE NOW?

Examples:

FieldServiceMobile change with:
- no deployment allowed;
- no runtime org execution;
- no physical mobile device;

Result:

QA REQUIRED: YES
QA EXECUTABLE NOW: NO
QA STATUS: DEFERRED

Do not spawn the QA subagent.

A route such as:

Builder → Reviewer → QA

describes the required lifecycle before acceptance.
It does not mean every stage must execute in the current turn.

## Runtime QA Execution Gate

Deployment availability alone does not make runtime QA executable.

For QA that requires functional execution, QA EXECUTABLE NOW requires all
mandatory prerequisites, including:

- deployed implementation where deployment is required;
- authenticated target org;
- authorization to create or modify controlled test data, either:
  - provided explicitly by the user; or
  - granted by CONTROLLED_TEST_DATA.md for the requested QA execution;
- ability to create suitable test records;
- required persona/session where relevant;
- required device when physical mobile behaviour is mandatory.

If mandatory runtime validation requires record mutation and neither explicit
user authorization nor project-policy authorization exists::

QA REQUIRED: YES
QA EXECUTABLE NOW: NO
QA STATUS: DEFERRED

Do not spawn QA merely because the metadata has been deployed.

---

## Promotion to Local

Promotion to Local is a technical promotion step, not final functional
acceptance.

For isolated-worktree implementations:

Builder
→ Reviewer
→ QA now, when executable
   OR
→ QA DEFERRED
→ User approval for promotion
→ Promotion to Local

After promotion, additional lifecycle stages may still be required:

Promotion to Local
→ deployment / runtime preparation
→ deferred QA
→ final user acceptance
→ commit / merge / push

Reviewer approval does not imply final user acceptance.

QA DEFERRED does not prevent promotion when promotion or deployment is required
to make QA executable.

Never interpret Reviewer approval as permission to modify the main checkout
without explicit user approval.

---

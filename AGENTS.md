# SinalCabo Project Instructions

These instructions apply only to the SinalCabo project.

Global working principles, role routing and reusable Salesforce engineering
standards are defined in:

~/.codex/AGENTS.md

---

## 1. Project Bootstrap

For non-trivial SinalCabo work, read:

- docs/PROJECT_CONTEXT.md
- applicable repository evidence
- project-specific documents referenced by PROJECT_CONTEXT.md

Do not import assumptions from other projects.

---

## 2. Salesforce Environment

Primary development environment:

SinalCabo_DEV

For Salesforce CLI operations use:

--target-org SinalCabo_DEV

Do not use another org unless explicitly instructed.

Production writes are not authorized by this file.

---

## 3. Project Domain

This project uses Salesforce Field Service.

Relevant domains include, where applicable:

- Work Orders
- Work Order Line Items
- Service Appointments
- Work Types
- Work Plans
- Work Steps
- Service Territories
- Service Resources
- skills
- crews
- scheduling
- optimization
- mobile
- offline
- inventory
- Assets
- Locations
- products and material consumption
- integrations

Apply Field Service-specific global guidance from ~/.codex/AGENTS.md and the
relevant global playbook.

---

## 4. Mobile and Offline

Technician-facing functionality must be evaluated offline-first.

When applicable, consider:

- offline priming;
- cached related data;
- mobile permissions;
- draft behaviour;
- synchronization;
- conflicts;
- retries;
- record availability;
- mobile Flow support;
- LWC compatibility;
- actual Field Service Mobile behaviour.

Do not assume desktop behaviour equals Field Service Mobile behaviour.

Do not claim mobile/offline validation unless the real execution path was
tested.

---

## 5. Work Order and Service Appointment

Treat Work Order and Service Appointment as distinct lifecycle entities.

Do not assume:

- completing a Service Appointment completes the Work Order;
- completing a Work Order completes all Service Appointments;
- status transitions propagate automatically;

unless confirmed by standard Salesforce behaviour, configuration or project
automation.

Inspect actual automation before making lifecycle conclusions.

---

## 6. Integration Context

The project includes external-system integration.

Use docs/PROJECT_CONTEXT.md and current project evidence to determine:

- systems involved;
- system-of-record ownership;
- API direction;
- triggers;
- payloads;
- retry behaviour;
- reconciliation;
- operational ownership.

Do not assume external-system behaviour not confirmed by project evidence.

Use the global Integration Specialist when integration-domain uncertainty is
the primary issue.

---

## 7. Controlled Test Data

Controlled test data may be created only according to:

~/.codex/playbooks/CONTROLLED_TEST_DATA.md

and any stricter SinalCabo-specific restrictions documented in
docs/PROJECT_CONTEXT.md or other explicit project instructions.

Use only SinalCabo_DEV unless explicitly instructed otherwise.

Create the minimum data required for the investigation.

Clean up temporary test records when appropriate.

---

## 8. Project Evidence

For project-specific conclusions, prefer current authoritative evidence.

Use, where relevant:

1. confirmed project decisions;
2. Decision Log;
3. PROJECT_CONTEXT.md;
4. latest validated project documentation;
5. current Salesforce metadata/data/runtime evidence;
6. meeting outcomes;
7. working documents;
8. assumptions.

Distinguish clearly:

- Confirmed Decision
- Project Fact
- Repository Fact
- Runtime Evidence
- Assumption
- Open Point
- Superseded

Do not convert working hypotheses into confirmed project decisions.

---

## 9. Safe Change Behaviour

Before implementation:

- confirm the target component;
- inspect current metadata;
- confirm dependencies;
- confirm expected behaviour;
- understand mobile/offline impact where applicable.

For meaningful implementation changes, prefer an isolated worktree.

Do not modify unrelated components.

Do not deploy broader metadata than required.

---

## 10. Project-Specific Escalation

Use global routing from:

~/.codex/playbooks/ROUTING.md

Examples for this project:

Unknown Field Service behaviour
→ Analyst

Uncertain external-system integration pattern
→ Integration Specialist

Unresolved architectural decision
→ Architect

Approved implementation
→ Builder

Independent technical review
→ Reviewer

Executable functional/mobile validation
→ QA

Do not spawn additional roles unless they add materially different evidence.
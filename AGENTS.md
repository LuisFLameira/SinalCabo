# AGENTS.md

## Project Context

For any non-trivial SinalCabo task, read:

docs/PROJECT_CONTEXT.md

before proposing or implementing changes.

PROJECT_CONTEXT.md is a point-in-time project snapshot and must not be assumed
to be newer than the authoritative project decisions in Google Drive.

If a task depends on a potentially newer business or architectural decision,
request or use current project documentation before implementation.

This repository contains a Salesforce implementation.

Primary domains may include:
- Salesforce Field Service
- Service Cloud
- Apex
- Lightning Web Components
- Flow
- Salesforce metadata
- integrations
- security
- DevOps

Always inspect the existing implementation before proposing or applying changes.

Do not assume Salesforce objects, fields, statuses, APIs, metadata types or Field Service capabilities exist unless confirmed in:
1. the repository;
2. the authenticated Salesforce org;
3. official Salesforce documentation.

---

## Salesforce CLI

Use Salesforce CLI for org interaction.

Always use an explicit target org.

Examples:

sf project retrieve start --target-org <alias>
sf project deploy start --target-org <alias>
sf apex run test --target-org <alias>

Never assume the default org is the intended target.

Before changing an org:
1. identify the target org;
2. inspect existing metadata;
3. explain the intended change;
4. make the smallest necessary modification;
5. validate;
6. review the resulting diff.

---

## Environment Safety

### GREEN
Developer or disposable sandbox.

Allowed:
- retrieve metadata;
- create test data;
- execute SOQL;
- run tests;
- validate metadata;
- deploy approved development changes.

### AMBER
Shared test, QA, UAT or integration environment.

Before writes:
- explain what will change;
- avoid destructive operations;
- avoid uncontrolled test data;
- preserve existing configuration.

### RED
Production.

Never without explicit user approval:
- deploy metadata;
- modify records;
- delete records;
- run data-fixing Anonymous Apex;
- change permissions;
- create test data;
- perform destructive operations.

Prefer read-only investigation.

---

## Salesforce Development

Prefer, when appropriate:

1. standard Salesforce configuration;
2. Flow;
3. invocable Apex;
4. Apex;
5. LWC;
6. external integration.

Do not force declarative solutions when they create worse architecture.

For Apex review:
- bulkification;
- governor limits;
- CRUD/FLS;
- sharing;
- transaction boundaries;
- recursion;
- idempotency;
- concurrency;
- retries;
- logging;
- testability.

For Flow review:
- entry criteria;
- bulk behaviour;
- recursion;
- fault paths;
- transaction behaviour;
- mobile compatibility;
- offline behaviour.

For SOQL:
- avoid queries in loops;
- consider selectivity and volume;
- never hardcode RecordType IDs;
- inspect assumptions about Record Types.

---

## Salesforce Field Service

Always distinguish:

- Work Order = work to execute
- Work Order Line Item = detailed work
- Service Appointment = schedulable visit
- Assigned Resource = assignment
- Service Resource = worker, crew or other resource

For scheduling distinguish:
- eligibility;
- feasibility;
- optimization.

Treat:
- Work Rules primarily as constraints;
- Service Objectives primarily as weighted goals.

For mobile functionality use an offline-first approach.

Always consider:
- offline priming;
- cache;
- sync;
- conflicts;
- retries;
- related data availability;
- mobile Flow limitations;
- offline LWC limitations;
- permissions;
- sharing.

Do not assume desktop behaviour equals Field Service Mobile behaviour.

---

## Metadata

Before modifying metadata:
- inspect existing metadata;
- preserve naming conventions;
- preserve unrelated settings;
- avoid rewriting whole XML files unnecessarily.

For Flow metadata:
- do not guess XML structures;
- prefer metadata retrieved from Salesforce as the source of truth;
- validate processType-specific restrictions;
- explicitly verify FieldServiceMobile limitations.

When custom fields are created:
- provide a useful Description;
- provide Help Text where appropriate.

---

## Testing

After implementation:

1. run git status;
2. inspect git diff;
3. validate metadata;
4. run relevant Apex tests;
5. test positive and negative scenarios;
6. test mobile/offline scenarios when relevant;
7. confirm no unrelated metadata changed.

Do not claim something works unless it was actually validated.

Always distinguish:
- validated;
- inferred;
- not tested.

---

## Git

Before changes:

git status

After changes:

git diff

Do not overwrite unrelated local changes.

Do not commit unless explicitly requested.

Never push unless explicitly requested.

Never force-push.

---

## Research Priority

For Salesforce behaviour prefer:

1. authenticated target org;
2. existing repository;
3. Salesforce Help;
4. Salesforce Developer documentation;
5. Salesforce Object Reference;
6. Salesforce Release Notes;
7. Salesforce Architects;
8. Salesforce Known Issues.

Do not use random public repositories as the primary source for Salesforce metadata syntax when Salesforce-generated metadata can be retrieved.

---

## Working Method

For non-trivial changes:

1. inspect;
2. explain findings;
3. propose a plan;
4. identify risks;
5. implement;
6. validate;
7. review the diff;
8. summarize exactly what changed.

If the requirement is ambiguous and materially affects architecture, ask before implementing.

For small, unambiguous changes, proceed directly but still validate.

Do not introduce unnecessary abstraction or custom code.

## Agent Roles

For architecture, design, ambiguity or cross-domain technical decisions, read:

docs/agent-roles/ARCHITECT.md

When acting as Architect, follow that role before producing implementation guidance.

For implementation tasks, read:

docs/agent-roles/BUILDER.md

When a BUILDER HANDOFF is provided, treat it as the implementation contract.
Do not reinterpret unresolved architecture while acting as Builder.
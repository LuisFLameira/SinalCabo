# Controlled Sandbox Test Data Policy

This policy applies to agents that are explicitly allowed to create or modify
controlled test data in the active Salesforce project.

## Target Environment

The target environment must be resolved from the active project's:

- AGENTS.md;
- PROJECT_CONTEXT.md;
- explicit project configuration;
- or direct user instruction.

Never assume a Salesforce org alias.

Controlled test-data writes are allowed only in an explicitly authorized
non-production environment.

Production data mutation is never authorized by this policy.

## Purpose

Controlled test data may be created when required to:

- investigate Salesforce standard behaviour;
- prove or disprove a technical hypothesis;
- execute a focused PoC;
- reproduce a defect;
- validate acceptance criteria;
- test lifecycle behaviour;
- test permissions, sharing or automation;
- prepare records for manual Field Service Mobile testing.

## Authorization

### Analyst

If the user explicitly asks to:

- test;
- prove;
- validate;
- reproduce;
- perform a PoC;
- investigate behaviour using the active project's authorized test environment;

the Analyst is authorised to create or modify controlled test data required for
that investigation.

If the user only asks for analysis or explanation, start read-only.
Ask for authorization before creating test data if mutation is not clearly
implied by the request.

If the user explicitly asks to test, prove, validate, reproduce or perform a PoC
in the active project's authorized test environment, the Analyst may create the
minimum controlled test data required by the investigation.

### QA

When the user explicitly requests QA execution against the active project's
authorized test environment, QA may create or modify controlled test data
required by the approved scenarios unless project instructions prohibit it.

## Allowed

When relevant to the scenario, agents may create controlled records such as:

- Account
- Contact
- Asset
- Location
- Product2
- ProductItem
- WorkType
- WorkOrder
- WorkOrderLineItem
- ServiceAppointment
- ServiceTerritory
- ServiceTerritoryMember
- ServiceResource
- Skill-related records
- ReturnOrder / ReturnOrderLineItem
- other standard or existing project records genuinely required by the test

Do not create data that is unrelated to the hypothesis or test.

## Not Allowed

Without separate explicit authorization:

- do not modify metadata;
- do not deploy metadata;
- do not create or modify Apex, Flow or LWC;
- do not modify org-wide Setup configuration;
- do not change existing business records merely because they are convenient;
- do not modify production data;
- do not commit or push;
- do not change integration endpoints or credentials;
- do not send intentional transactions to external production systems.

## Test Data Isolation

Prefer newly-created test records over modifying existing records.

Never perform destructive experimentation on production-like existing records
when equivalent controlled data can be created.

Where an appropriate existing Name, Description or similar field is available,
use a recognizable marker such as:

AI_POC | <date> | <purpose>

Do not assume such a field exists and do not create a custom field merely for
test-data marking.

## Minimum Data Principle

Create the smallest data graph that can answer the question.

Example:

If testing Work Order lifecycle with two visits, do not create a complete
customer/inventory/scheduling hierarchy unless it is required for the behaviour
under test.

## Existing Configuration

Use existing configuration where practical.

Do not modify configuration merely to make a PoC pass.

If existing configuration prevents the test, report that as evidence.

## Evidence

Record every material record created or modified.

Include:

- object;
- record identifier;
- purpose;
- relevant initial state;
- final state.

Never include credentials, tokens or secrets.

## Cleanup

At the end of the investigation:

- delete disposable test data when deletion is safe and useful;
- retain records required for subsequent manual/mobile testing;
- do not perform risky cascading deletes merely for cleanliness.

Report retained test data explicitly.

## Evidence Classification

Use these classifications:

PROVEN
Directly demonstrated by controlled execution.

OBSERVED
Observed in current configuration/data but not proven universally.

INFERRED
Derived from evidence but not directly executed.

NOT TESTED
Not validated.

Do not present OBSERVED or INFERRED behaviour as PROVEN.

## Stop Conditions

Stop the experiment when:

- the hypothesis has been answered;
- additional testing would not materially change the conclusion;
- required metadata/configuration changes would exceed Analyst or QA authority;
- external integrations could cause uncontrolled side effects;
- required mobile/device behaviour cannot be executed;
- a human architecture decision is required.
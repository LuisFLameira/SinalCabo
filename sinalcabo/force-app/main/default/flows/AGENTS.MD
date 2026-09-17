# Salesforce Flow Instructions

These instructions apply specifically to Salesforce Flow metadata.

## Documentation Scope

Be precise about the scope of Salesforce documentation.

Do not apply limitations documented specifically for:
- Data Capture
- CRM Core mobile flows
- desktop Screen Flows
- managed package flows
- Lightning Web Components

to generic Field Service Mobile Flows unless Salesforce documentation
explicitly states that the limitation applies to Field Service Mobile Flows.

When citing a limitation:
1. identify the Salesforce feature or Flow type it applies to;
2. verify that the current Flow uses that feature;
3. do not generalize section-specific limitations.

## Field Service Mobile

For processType = FieldServiceMobile:

- verify behaviour against current official Salesforce documentation;
- use Id, ParentId and UserId according to Field Service Mobile context;
- do not assume desktop Flow behaviour applies;
- treat Get Records as potentially cached in mobile;
- consider offline priming and synchronization;
- remember that each Create, Update, or Delete element executes as a
  separate transaction in Field Service Mobile;
- explicitly identify partial-update risks when multiple CRUD operations exist.

Do not classify a Flow structure as unsupported merely because the same
structure is restricted in Data Capture.

## Flow Metadata

Never invent Flow XML.

Prefer:
1. metadata retrieved from the target org;
2. known-working metadata already in this repository;
3. official Salesforce documentation.

Before changing a Flow:
- inspect the full Flow;
- inspect its variables;
- inspect record lookups;
- inspect CRUD elements;
- inspect Quick Action / mobile launch context;
- identify offline implications.

After changing a Flow:
- validate XML;
- inspect git diff;
- validate against the target org;
- test in the actual Field Service Mobile app when applicable.

A successful metadata deployment does not prove mobile runtime compatibility.

## Validation Language

Always distinguish:

- Validated in Salesforce org
- Validated in Field Service Mobile app
- Validated only at metadata/deployment level
- Inferred from documentation
- Not tested
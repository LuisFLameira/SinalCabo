# PROJECT_CONTEXT.md

> Persistent technical context for coding agents and Salesforce Technical Architects working on the SinalCabo repository.
>
> Consolidated from the local Salesforce DX source and the SinalCabo Field Service documentation available in Google Drive.
>
> This is a point-in-time context snapshot. It is not, by itself, formal approval of the architecture or of any implementation found in the repository.

## Governance and Classification Rules

Every statement should be interpreted using these labels:

- **Salesforce Standard:** Native Salesforce or Salesforce Field Service capability. This does not establish that it is configured, suitable or approved for SinalCabo.
- **SinalCabo Fact:** Project-specific business or system behaviour supported by evidence.
- **Confirmed Decision:** Explicitly recorded as decided/confirmed in the Decision Log or directly approved by the appropriate client/decision owner.
- **Working Direction:** Current preferred design, still requiring confirmation, detailed design or production validation.
- **Repository Fact:** Confirmed in local source. It proves implementation or metadata existence only.
- **PoC Only:** Implemented or tested to obtain evidence; not an approved production architecture.
- **Assumption:** Unconfirmed hypothesis.
- **Open Point:** Unresolved business, technical or scope decision.
- **Superseded:** Earlier position that must no longer be used as the current design.

Keep these three dimensions separate:

1. What is implemented.
2. What the target architecture currently proposes.
3. What is approved and ready for production.

## Source Access Model

Google Drive is not assumed to be automatically or permanently accessible to future agents.

The SinalCabo Google Drive documentation was explicitly accessed during this consolidation, including the Project Cheat Sheet, Decision Log, Data Model Hypothesis, discovery/session notes, Open Points, user-story backlog, PoC reports, architecture deltas and production-readiness checklist.

Rules for future agents:

- Explicitly access or refresh the SinalCabo Google Drive folder whenever current decisions, open points, recent meeting outcomes or scope status are material to a task.
- Do not assume that the Drive content has been synchronized into the repository.
- Do not assume that this file reflects decisions made after its consolidation date.
- When Drive access is unavailable, treat this file only as a point-in-time local snapshot.
- Record any material conflict between this file, current Drive documents, the repository and an authenticated org.
- Do not silently promote a newer-looking document to decision authority; verify its status and decision evidence.

## Context Maintenance

**Last consolidated:** 2026-09-17.

Refresh this document after any of the following:

- A decision is formally confirmed.
- A previous decision is superseded or rejected.
- A material architecture boundary or data-model direction changes.
- A major PoC produces evidence that changes an assumption, blocker or implementation option.
- An integration contract is confirmed or materially revised.
- Production-readiness, licensing, mobile, security, cutover or support status changes.

Maintenance rules:

- Repository changes alone do not constitute decision changes.
- New or changed metadata must be classified separately from the decision status that may have motivated it.
- A refresh must consider:
  1. the current Decision Log;
  2. newer relevant Google Drive sources;
  3. the current repository;
  4. deployment/test evidence;
  5. authenticated org state when relevant and when an explicit target org is available.
- Update the consolidation date whenever the document is materially refreshed.
- Preserve superseded decisions where they are needed to prevent regression to an obsolete design.
- Do not erase unresolved conflicts merely because one implementation already exists.
- Do not treat this file as the original evidence for a decision.

## AI-Generated Artefact Rule

A significant part of the repository metadata and technical documentation was created with AI assistance from discovery-session material.

Therefore:

- AI-created implementation is not decision authority.
- AI-created documentation is not decision authority.
- Repository existence proves only that an artefact was implemented or retrieved into source.
- The existence of fields, Flows, Apex, statuses, Entitlements, Entitlement Processes, Milestones, Custom Metadata, permission sets or other metadata does not prove formal approval.
- A technically coherent implementation may still be exploratory, provisional, superseded or inconsistent with the latest client decision.
- No repository artefact may be promoted to **Confirmed Decision** without explicit decision evidence.
- Comments, labels and descriptions inside metadata may reflect the design understanding at the time they were generated; they are useful evidence of implementation intent, not approval.
- Where decision evidence is missing, classify the artefact as Repository Fact, PoC Only, Working Direction, Assumption or Open Point.

## Confirmed Decision Traceability Rule

Every statement classified as **Confirmed Decision** must reference, when available:

- a Decision Log ID;
- an explicit meeting/client decision and date;
- an approved baseline and date; or
- another identifiable approval record.

If explicit decision evidence cannot be located:

- downgrade the statement to **Working Direction**;
- do not infer approval from implementation;
- do not invent a Decision Log ID, approver, meeting or date.

`PROJECT_CONTEXT.md` must never be cited as the evidence that a decision was confirmed. It is a consolidation of evidence held elsewhere.

## Source Authority Hierarchies

### A. Implementation Truth

Use this hierarchy to determine what is actually present or running:

1. Authenticated target org inspection.
2. Current repository source.
3. Deployment, validation or test evidence.
4. Project documentation.

Repository metadata does not prove deployment. Documentation does not prove implementation.

### B. Decision Truth

Use this hierarchy to determine what is approved:

1. Confirmed Decision Log entry.
2. Explicit meeting/client decision by the appropriate owner.
3. Approved project baseline.
4. Working design or architecture direction.
5. Repository artefact.
6. AI-generated proposal.

Implementation truth and decision truth may disagree. Report the disagreement; do not resolve it by assuming the implementation is approved.

# 1. Project Purpose and Scope

**SinalCabo Fact:** The project introduces Salesforce Field Service for SinalCabo’s REXT operation, initially centred on the NOS operation in Greater Lisbon.

**Confirmed Decision:** Salesforce is the operational Field Service execution layer. It does not replace PHC or the NOS platforms.  
**Evidence:** Project Cheat Sheet, Cold Start baseline dated 2026-09-17; TO-BE Validation & Demo meeting dated 2026-09-17.

Expected Salesforce responsibilities include:

- Work Order intake and classification.
- Scheduling and dispatch.
- Field Service Mobile execution.
- Operational statuses and evidence.
- Time, pause and SLA tracking.
- Operational material consumption, transfer and return facts.
- Integration monitoring and exception handling.
- Approved operational reporting.

Conditional or scope-gated capabilities include:

- RRT/IDR2 project visibility or integration.
- NOS auto import and reconciliation.
- Rich photo annotation and multi-photo UX.
- Broader project management.
- Advanced scheduling optimization.
- Exact-location integration from NOS.
- Large-scale historical evidence migration.

Full replacement of PHC, full RRT replication, unapproved writes to NOS platforms and indiscriminate migration of the approximately 700 GB legacy evidence estate are not part of the current baseline.

# 2. Current Architecture

## Target system boundaries

- **Confirmed Decision:** Salesforce Field Service owns operational field execution.  
  **Evidence:** Project Cheat Sheet, Cold Start baseline dated 2026-09-17; TO-BE Validation & Demo meeting dated 2026-09-17.
- **Confirmed Decision:** PHC remains authoritative for ERP article identity, confirmed/financial stock, valuation and ERP documents.  
  **Evidence:** Project Cheat Sheet, Cold Start baseline dated 2026-09-17; TO-BE Validation & Demo meeting dated 2026-09-17.
- **SinalCabo Fact:** NOS/NetGuard/PNI remain authoritative for their external work and state data.
- **Open Point:** RRT/IDR2 remains an upstream project/preparation domain whose integration and Phase 1 scope are unresolved.

## Current repository implementation

**Repository Fact:** The Salesforce DX project is under `sinalcabo/`, uses API version `67.0` and has no namespace.

The repository contains:

- Read-only NOS Field Force Management API integration.
- Five-minute polling implementation using scheduled Apex and Queueables.
- Named Credential `SC_NOS_FFM_API`.
- External Credential `SC_NOS_FFM_Cred` using OAuth client credentials.
- NOS parsing, mapping, Work Order upsert, retry/suspension and watchdog logic.
- Manual PNI file import through LWC/Apex.
- Integration batch and exception objects.
- Work Order and Service Appointment automation.
- TE/TEC milestone and Entitlement Process metadata.
- Field Service Mobile Flows for start, close and material return.
- Cell extraction, classification and coordinate propagation.
- Permission sets for NOS integration, dispatch and back office.

These artefacts may include AI-assisted exploratory implementation. Their presence does not establish approval.

**Not verified:** Deployment state, scheduled jobs, Entitlement Process activation, seed data, package versions, mobile configuration or runtime behaviour in any org.

**Repository Fact:** No PHC integration implementation was found. PHC integration remains target architecture and contract design.

# 3. Core Salesforce Data Model

## Salesforce Standard roles

- `WorkOrder`: work obligation or executable work package.
- `WorkOrderLineItem`: detailed work where separate semantics justify it.
- `ServiceAppointment`: schedulable and executable visit.
- `AssignedResource`: assignment of a resource to a visit.
- `ServiceResource`: schedulable worker, crew or other resource.
- `ServiceTerritory` and `ServiceTerritoryMember`: territory structure and resource membership.
- `SkillRequirement` and `ServiceResourceSkill`: capability-based eligibility.
- `Product2`: product catalogue identity.
- `Location` and `ProductItem`: inventory position by product and location.
- `ProductConsumed`: material consumed by work.
- `ProductTransfer`: inventory transfer.
- `ReturnOrder` and `ReturnOrderLineItem`: reverse logistics.
- `SerializedProduct` and `ProductConsumedState`: serialized unit identity and consumption relationship.
- `Entitlement`, `EntitlementProcess` and `EntityMilestone`: entitlement and milestone framework.

## SinalCabo-specific objects

**Repository Facts:**

- `Celula__c`: network-cell reference including technology, territory and location data.
- `Lote_Integracao__c`: integration run/batch.
- `Ocorrencia_Integracao__c`: integration warning, rejection or exception.
- `Paragem_Ordem__c`: Work Order pause interval.
- `SC_NOS_Estado__c`: NOS polling cursor, kill-switch and suspension state.
- `SC_NOS_Polling__e`: optional polling request Platform Event.
- `SC_FS_SLA_OT__mdt`: current Work Type-to-Entitlement/Business Hours routing implementation.
- `Sistema_Cliente__mdt`: source-system configuration.

None of these repository artefacts should be treated as an approved data-model decision solely because they exist.

## Principal Work Order dimensions

The current source separates:

- Internal `WorkOrder.Status`.
- NetGuard status in `Estado_Cliente__c`.
- PNI status in `Estado_Aceitacao_Cliente__c`.
- Billing visibility in `Estado_Facturacao__c`.
- Cadastro outcome in `Resultado_Cadastro__c`.
- Pause reason and responsible party.
- TE and TEC timestamps.
- NOS order, incident, contract, group, priority and technician identifiers.
- Cell, technology, territory and classification confidence.
- Integration signatures, last-read timestamp and source batch.

**Confirmed Decision:** External, internal, visit, cadastro and commercial states are separate dimensions.  
**Evidence:** Decision Log D-215; reinforced in the TO-BE Validation & Demo meeting dated 2026-09-17.

The specific fields and transitions remain subject to approval.

# 4. Work Order and Service Appointment Lifecycle

**Confirmed Decision:** Work Order represents the work/business obligation and Service Appointment represents the concrete schedulable/executable visit.  
**Evidence:** TO-BE Validation & Demo meeting dated 2026-09-17, section “Work Order / Service Appointment”; Project Cheat Sheet Cold Start baseline dated 2026-09-17.

**Working Direction:**

- A revisit normally creates another Service Appointment under the same Work Order.
- WOLI or child Work Order should be used only when justified by independent lifecycle, assignment, SLA, material, remuneration or reporting requirements.

**Open Point:** Final OT → subwork → visit → resource cardinality remains unresolved, particularly for parallel teams and independently completed construction components.

The lifecycle must keep distinct:

1. External intake/state.
2. Internal Work Order state.
3. Service Appointment execution.
4. Pause/pending state and reason.
5. Cadastro progression.
6. Commercial/billing progression.
7. TE/TEC milestones.

**Repository Fact / PoC Only:**

- `SC_Iniciar_OT_From_ServiceAppointment` sets both Service Appointment and Work Order to `In Progress`.
- `SC_Fechar_OT_From_ServiceAppointment` sets both to `Completed`.
- Supporting Flows populate actual start/end and `Data_Fecho_Tecnico__c`.

**Open Point / Known mismatch:** The current close Flow conflates visit completion and Work Order completion. The target rule is not approved. A completed visit may need to leave the Work Order awaiting cadastro, validation, another visit or another component.

Starting or closing work in Salesforce must not be assumed to update NetGuard or PNI.

# 5. Work Types / Work Plans / Work Steps

**Working Direction:** Work Types should represent materially different execution patterns rather than blindly replicating every external code.

**Repository Facts:** Work Type fields include:

- `Codigo_Cliente__c`
- `Familia__c`
- `Dentro_Avenca__c`
- `TE_Minutos__c`
- `TEC_Minutos__c`
- penalty and measurement-unit fields
- standard `EstimatedDuration`

**Salesforce Standard:** `EstimatedDuration` supports scheduling. It is not inherently SLA, MTTR or contractual duration.

**Working Direction:** Work Type/work-family-to-SLA mapping should be versioned and outside Apex where practical.

**Salesforce Standard:** Work Plans and Work Steps provide procedural/checklist structure. They do not replace independently assignable work.

**Repository Fact:** Work Plan, Work Plan Template and Work Step layouts/sharing metadata exist.

**Open Point:** No approved project-specific Work Plan/Work Step catalogue was established. Mandatory steps and evidence must come from an approved Work Type matrix, not free-text inference.

# 6. Scheduling and Resource Model

**Working Direction:** Manual dispatch is the MVP baseline. Advanced optimization is outside the current baseline.

If native Schedule or bulk Schedule is used, a small explicit Scheduling Policy will still be required and tested.

Resource directions:

- Independently working technicians should be individual Service Resources.
- Service Crew should be reserved for stable teams that are scheduled and operate as one unit.
- Ad-hoc helpers may require multiple Assigned Resources.
- Work on separate dates, components or locations may require separate Service Appointments or independently executable work records.

These are current architecture directions, not universally approved rules for every process.

Territory direction:

- One primary membership represents habitual coverage.
- Secondary memberships represent validated persistent coverage.
- Occasional exceptions remain manual in MVP.
- Technology/skill eligibility takes precedence over simplistic geographic adjacency.
- Historical six-zone designs remain provisional until final boundaries and memberships are approved.

Availability:

- **Salesforce Standard:** Operating Hours and Holidays provide base availability.
- **PoC Evidence:** The tested Resource Absence required `Approved=true` to affect scheduling availability and appear on the Gantt.
- **Working Direction:** Rotating piquete should not be represented by continually rewriting base Operating Hours.

# 7. Mobile and Offline Architecture

**Working Direction / Architecture Guardrail:** Technician-critical actions should be offline-first.

Preferred implementation order:

1. Salesforce Field Service standard mobile behaviour.
2. Field Service Mobile Flow.
3. Supported offline data access and priming.
4. Custom LWC only for a proven gap and after offline capability is demonstrated.

**Repository Fact:** Active Field Service Mobile Flow metadata includes:

- `SC_Iniciar_OT_From_ServiceAppointment`
- `SC_Fechar_OT_From_ServiceAppointment`
- `SC_Retornar_Material_From_WorkOrder`
- `TEST_Field_Service_Mobile_Flow`

Activation in metadata does not prove production approval or successful offline execution.

Mobile acceptance must cover:

- Full offline execution.
- Interrupted sync and retry.
- Duplicate prevention.
- Briefcase/offline priming.
- Android and iOS configuration.
- Fresh authentication after Connected App changes.
- Actual licence and permission behaviour.
- Photo/file evidence and storage constraints.

## Multiple inventory Location PoC

**PoC Evidence:** Multiple inventory Locations were validated on a real Salesforce Field Service Mobile Android device using `ENABLE_MULTIPLE_LOCATIONS` and a parent/direct-child Location hierarchy.

This proves only that:

- The mobile application can expose/select multiple eligible inventory Locations under the tested configuration.
- The parent/direct-child Location hierarchy can participate in the tested visibility pattern.

It does not prove:

- The final shared subcontractor inventory architecture.
- That Crew ownership or Crew membership provides the required access.
- The production sharing model.
- Production offline priming.
- Stock ownership and accountability.
- Contractor licence behaviour.
- PHC reconciliation.
- Concurrency or insufficient-stock behaviour.
- Android/iOS parity.

The earlier conclusion that multiple Location visibility was unavailable is superseded by this later device validation. The broader subcontractor architecture remains open.

# 8. Inventory and Material Consumption

**Confirmed Decision:** Salesforce stock-bearing categories are New and Reusable only.  
**Evidence:** Decision Log D-194, dated in the 2026-09-17 TO-BE validation delta.

**Confirmed Decision:** Scrap is not a Salesforce Location/ProductItem inventory balance; PHC retains scrap custody and ERP semantics.  
**Evidence:** Decision Log D-194.

**Working Direction:**

- A logical parent Location may exist without stock.
- Final Location cardinality must reflect actual PHC ownership and stock keys.
- Internal and subcontractor stock models may differ.

Product identity:

- **Confirmed Decision:** A reusable PHC reference with its own independent balance, such as `A123`, is a separate Product2 related to original `123`.  
  **Evidence:** Decision Log D-196.
- **Working Direction:** PHC article reference is the canonical stock-bearing identity.
- External NOS/PNI/manufacturer/barcode identifiers may be aliases when they do not own stock.

Consumption:

- **Salesforce Standard:** ProductConsumed represents work consumption.
- **Working Direction:** Use standard inventory processing where it applies; do not reproduce standard quantity arithmetic in custom Apex.
- Material movements must preserve effective time.
- Corrections should remain append-only through compensating movements.
- Material posting must remain independent of cadastro and billing.

Serialized inventory:

- **Working Direction / PoC Gate:** Use ProductItem, SerializedProduct, ProductConsumed and ProductConsumedState for unit-level traceability.
- Exact scan/search, offline retry, duplicate serial, wrong Location and PHC integration behaviour remain unproven.

# 9. Material Returns

**Confirmed Decision:** Removed material is represented through ReturnOrder and ReturnOrderLineItem, and a reusable return does not immediately increase Salesforce reusable stock.  
**Evidence:** Decision Log D-195.

Current target sequence:

1. Technician identifies removed Product2, quantity and Reusable/Scrap intent.
2. Salesforce records the return fact.
3. PHC consumes the return.
4. For Reusable, PHC processes/converts the original reference to the reusable reference.
5. PHC publishes the confirmed reusable balance.
6. Only that confirmed balance becomes available for Salesforce consumption.
7. Scrap does not return as a Salesforce stock balance.

**Superseded:** Immediate reusable restock through a local ProductTransfer or direct ProductItem increase.  
**Evidence:** Decision Log D-195 and the 2026-09-17 TO-BE validation delta.

**Repository Fact / PoC Only:** `SC_Retornar_Material_From_WorkOrder` creates:

- A Draft ReturnOrder.
- A ReturnOrderLineItem.
- `Restock` for Reusable.
- `Discard` for Scrap.

Current limitations:

- The Flow does not explicitly link the created return records to the Work Order.
- PHC acknowledgement and confirmed-balance return are not implemented.
- Final Scrap ProcessingPlan semantics remain open.
- Product selection across all active Product2 records is not an approved production UX.

# 10. SLA / Entitlement Architecture

**Salesforce Standard:** A Work Order can reference an Entitlement, whose Entitlement Process may create milestones.

**Working Direction:**

- Resolve the applicable Entitlement from Work Type/work family through versioned configuration.
- Keep TE and TEC as separate milestones.
- Keep contractual calendars separate from resource scheduling calendars.

**SinalCabo Fact:** A 20-consecutive-calendar-day rule was discussed for specific contractual cases. It is not a universal rule for every Work Type.

**Repository Facts:**

- Milestone Types `TE (intervenção)` and `TEC (cadastro)` exist.
- Multiple Entitlement Process variants exist.
- `SC_SlaCalculadorPrazo` reads TE/TEC minutes from Work Type.
- `SC_FS_Ordem_SLA_Arranque` uses `SC_FS_SLA_OT__mdt`.
- `SC_FS_Ordem_SLA_Milestones` completes milestones from Work Order timestamps.

These are implemented designs, not proof of an approved SLA architecture.

**Known risk:** `SC_FS_SLA_OT__mdt` records contain environment-specific Work Type, Entitlement and Business Hours IDs. The mapping is not portable as currently represented.

**Open Point:** Authoritative Work Type/SLA matrix, effective dates, contracting Account, Entitlement records, calendars, pause rules, penalties and process-version migration.

# 11. PNI / NetGuard State Model

The following dimensions must remain separate:

- NetGuard status.
- PNI/cadastro acceptance status.
- Internal Work Order state.
- Service Appointment execution state.
- Pause/pending interval and reason.
- TE/TEC milestone state.
- Commercial/billing state.

Known NetGuard values implemented in the repository include:

- `ASSIGNED_TO_COMPANY`
- `ASSIGNED_TO_USER`
- `WORK_IN_PROGRESS`
- `PENDING`
- `RESOLVED`
- `CLOSED`

**SinalCabo Facts:**

- NetGuard is operationally required for the NOS handshake.
- The current API is read-only.
- NetGuard `WORK_IN_PROGRESS` does not prove actual technician start.
- `RESOLVED` is a NOS monitoring/acceptance state, not internal completion.
- Repeated Work In Progress/Pending cycles occur.
- PNI files are snapshots and can omit transient transitions.

**Repository Facts:**

- NOS API processing writes `Estado_Cliente__c` but normally does not alter internal Work Order Status after creation.
- PNI processing writes PNI-owned fields and preserves existing internal Status.
- API and PNI use separate signatures.
- `Referencia_Ordem_Cliente__c` is used as the Work Order external key.

**Open Point:** Final state-transition matrix, event preservation and source precedence.

Do not infer “without cadastro” solely from absence in PNI.

# 12. TE / TEC Timing Model

Current terminology:

- **TE:** execution/intervention clock.
- **TEC:** cadastro-delivery clock.

Historical TEQ/TSE terminology must not be reintroduced without contractual confirmation.

**Working Direction:**

1. Authoritative assignment/start event begins TE.
2. Technical completion ends TE.
3. Awaiting-cadastro transition starts TEC.
4. Cadastro delivery ends TEC.
5. Pause/resume preserves accumulated time unless the approved rules state otherwise.

Repository timestamps include:

- `Data_Atribuicao_Cliente__c`
- `Data_Fecho_Tecnico__c`
- `Data_Producao__c`
- `Data_Entrega_Cadastro__c`
- `Data_Limite_Acordada__c`

**Repository Facts:**

- `Paragem_Ordem__c` stores pause intervals.
- `SC_FS_Ordem_Paragem` sets or clears `WorkOrder.IsStopped`.
- `Minutos_Parado__c` aggregates pause minutes.
- Provisional pause values exist in Global Value Sets.

**Implemented / not approved:** Current provisional reasons include Material da NOS, Autoridade, Licenciamento, Acesso ao local and Meios da SinalCabo.

**Open Point:** Final reason catalogue, approval, evidence and effect on TE and TEC. Generic `Pending` must not automatically be treated as an SLA pause.

# 13. PHC Integration

**Working Direction:** Salesforce exposes versioned REST business APIs; PHC/Winsig consumes them and returns acknowledgements and confirmed balances.

Expected Salesforce-to-PHC capabilities:

- Consumption.
- Return.
- Transfer.
- Reversal/correction.
- Services or hours where approved.
- Effective timestamp, Work Order, Location, technician and serial details.

Expected PHC-to-Salesforce capabilities:

- Canonical products.
- Aliases/barcodes.
- Location mappings.
- Confirmed balances.
- Acknowledgements and rejection details.

Required contract characteristics:

- External idempotency key.
- Stable cursor/pagination.
- Per-line processed/rejected/deferred result.
- Retry and replay.
- `asOf`/watermark semantics.
- Protection of post-cutoff or unacknowledged Salesforce movements.
- Reconciliation.
- Heartbeat and monitoring.
- Separate material, service and commercial contracts.

**Working Direction:** Hourly PHC polling is the current operational target. It is not a confirmed production contract.

**Open Points:**

- Authentication method.
- Environment and credential ownership.
- Movement/document mapping.
- Queue pagination.
- Opening balance.
- Balance reconciliation.
- On-demand Location refresh.
- Analytic-centre formula ownership.
- Month-end offline movements.
- Same-intervention reusable-material latency.

**Repository Fact:** No PHC integration implementation or PHC credential metadata exists in current source.

# 14. Other Integrations

## NOS Field Force Management API

**Repository Fact:** Read-only GET integration exists through `SC_NOS_FFM_API`.

Implemented design includes:

- Window-based list/detail calls.
- Portugal-local-time parameter formatting.
- Scheduled polling structure.
- Queueable processing.
- Window splitting and backoff.
- Work Order upsert.
- Integration batches and exceptions.
- Historical-load support.

This does not prove deployment or formal approval of every mapping.

## PNI file intake

**Repository Fact:** Implemented through `scPniCarregamento` and Apex services.

Capabilities include:

- Manual upload.
- Chunk processing.
- Simulation.
- Header validation.
- Work Order upsert.
- Rejected-row logging.
- Reprocessing.
- Custom permission.

## RRT / IDR2

No integration implementation was identified.

**Confirmed Decision:** Mass manual Work Order creation is not accepted as the target replacement for high-volume RRT project control.  
**Evidence:** Decision Log D-203; explicit client challenge recorded in the TO-BE Validation & Demo meeting dated 2026-09-17.

**Open Point:** Phase 1 RRT/IDR2 scope and API availability.

## NetGuard outbound updates

No supported write interface is confirmed. Dual entry remains a known external constraint.

## Exact intervention location

**SinalCabo Fact:** The current NetGuard API does not provide dedicated structured intervention latitude/longitude.

Cell coordinates are coarse context only. Exact-coordinate integration depends on new NOS fields.

# 15. Billing / Autos Context

Billing must remain separate from technical completion and stock acknowledgement.

Distinct concepts include:

- Within-retainer/no separate invoice.
- Ready for future NOS auto.
- Included in auto.
- Invoiced.
- Paid/received, if required.

**SinalCabo Facts:**

- NOS produces the auto/autofatura.
- `Concluído Remunerado` means eligible for a future auto, not invoiced.
- PHC does not currently represent a Work Order as a commercial entity.
- PHC material dossiers are logistical, not proof of remuneration.
- Autos may be aggregated and are currently registered manually.

**Evidence:** Decision Log D-239 and D-251; Contracts, SLA, Billing, States & Territory Reconciliation meeting dated 2026-09-11.

**Open Scope Gate:** Auto import/reconciliation requires:

- Canonical import template.
- Source mapping.
- Stable matching key and suffix handling.
- RIC/RECST semantics.
- Aggregation rules.
- Unmatched/ambiguous queues.
- Named operational owner.
- Correction process.
- Auditable batch/line import.

**Repository Fact:** `Estado_Facturacao__c` contains billing-state values. This does not prove that an approved integration or operational process populates them.

# 16. Security and Sharing

**Repository Facts:**

- Work Order and Service Appointment internal/external sharing are `Private`.
- Permission sets exist for NOS integration, dispatch and back office.
- `SC_FS_Integracao_NOS` references the NOS External Credential principal.
- PNI import uses custom permission `SC_FS_Importar_PNI`.
- Secrets are not stored in source.

These facts do not prove an approved production sharing model.

Required personas include:

- Dispatcher.
- Internal Mobile Worker.
- Contractor Mobile Worker.
- Supervisor.
- Back office.
- Inventory/Logistics.
- Integration User.
- Administrator.

**Open Points:**

- Contractor licence SKU.
- User-versus-Contact model.
- Employer isolation.
- Supervisor visibility.
- File/photo sharing.
- Shared inventory permissions.
- Claim/release/reassignment rights.
- Final CRUD/FLS.
- Mobile and offline data visibility.

Validate access using a real licensed user, sharing configuration, current mobile session and primed records.

# 17. Confirmed Decisions

Only decisions with explicit evidence are retained here.

- **Salesforce is the operational Field Service execution layer.**  
  Evidence: Project Cheat Sheet Cold Start baseline dated 2026-09-17; TO-BE Validation & Demo meeting dated 2026-09-17.

- **PHC remains authoritative for ERP article identity, confirmed/financial stock, valuation and ERP documents.**  
  Evidence: Project Cheat Sheet Cold Start baseline dated 2026-09-17; TO-BE Validation & Demo meeting dated 2026-09-17.

- **Work Order represents the work/business obligation; Service Appointment represents the schedulable/executable visit.**  
  Evidence: TO-BE Validation & Demo meeting dated 2026-09-17; Project Cheat Sheet Cold Start baseline dated 2026-09-17.

- **External status, internal Work Order state, Service Appointment state, cadastro, SLA and commercial state are separate dimensions.**  
  Evidence: Decision Log D-215.

- **Salesforce inventory carries New and Reusable stock only; Scrap does not create a Salesforce inventory balance.**  
  Evidence: Decision Log D-194.

- **Removed material is represented through ReturnOrder and ReturnOrderLineItem, and reusable material becomes Salesforce stock only after PHC processing and confirmed-balance publication.**  
  Evidence: Decision Log D-195.

- **An independently stocked reusable reference is a separate Product2, not merely an alias.**  
  Evidence: Decision Log D-196.

- **Selected Work Order context must be mirrored to Service Appointment for Dispatcher Console filtering/display.**  
  Evidence: Decision Log D-198.

- **Pause/Pending is distinct from Close; detailed reasons and SLA effects remain open.**  
  Evidence: Decision Log D-202.

- **Mass manual Work Order creation is not the accepted target solution for RRT project control.**  
  Evidence: Decision Log D-203; explicit client challenge in the TO-BE Validation & Demo meeting dated 2026-09-17.

- **PHC stock acknowledgement is not evidence that a Work Order was included in an auto or remunerated.**  
  Evidence: Decision Log D-239 and D-251; Contracts/SLA/Billing session dated 2026-09-11.

## Current Working Directions

- Manual dispatch as MVP.
- Advanced optimization deferred.
- Individual Service Resources for independently working technicians.
- Service Crew only for genuine stable schedulable teams.
- Primary territory plus validated secondary memberships.
- Skills/technology as meaningful eligibility constraints.
- Offline-first technician-critical mobile flows.
- Standard inventory records and stock processing before custom arithmetic.
- ProductTransfer for urgent same-nature technician-to-technician handoff.
- Work Type/work-family-to-Entitlement mapping through versioned configuration.
- Sequential TE then TEC timing.
- Hourly PHC polling target.
- Salesforce versioned REST surface consumed by PHC.
- Append-only corrections through reversal and replacement.
- Exact coordinates consumed from NOS if/when structured fields become available.
- Stable canonical template if auto import is approved.

## Implemented / PoC Designs Not Yet Approved

- NOS API polling cadence and detailed mappings.
- PNI upload and upsert implementation.
- Current Work Order and Service Appointment custom fields.
- Current mobile Start and Close Flows.
- Current Return Material Flow.
- Current simultaneous Work Order/Service Appointment completion.
- Current pause reasons and responsibilities.
- Current Entitlement Processes and Milestone configuration.
- `SC_FS_SLA_OT__mdt` routing records.
- Current TE/TEC Apex calculator.
- Current Work Type TE/TEC values.
- Current permission-set design.
- Cell text extraction and coordinate propagation.
- Resource Absence behaviour demonstrated with `Approved=true`.
- Initial Crew-owned inventory test.
- Validated Android multiple-inventory-Location visibility using `ENABLE_MULTIPLE_LOCATIONS` and parent/direct-child Locations.
- Any AI-generated configuration or implementation without matching decision evidence.

# 18. Assumptions

Revalidate before implementation:

- `Referencia_Ordem_Cliente__c` is unique and stable across systems.
- PHC article codes are unique, stable and not recycled.
- Hourly PHC polling is viable.
- NetGuard API coverage is sufficient for intended MVP families.
- Cell-to-territory mapping is sufficiently reliable after human confirmation.
- Existing Work Type TE/TEC values come from an authoritative catalogue.
- The selected serialized-inventory model is available and suitable.
- Mobile priming can include every record required offline.
- External partners can deliver the missing contracts and support.
- Environment-specific reference data can be reproduced safely.

# 19. Open Architectural Decisions

- OT → subwork → visit → resource cardinality.
- WOLI, child Work Order or another record for autonomous components.
- Multi-team and parallel-work model.
- Final Work Order and Service Appointment lifecycle.
- Supervisor completion gate.
- Claim, release and reassignment.
- Piquete roster and one-active-task rule.
- Final territories and skills.
- Final shared subcontractor inventory architecture.
- Stock ownership and sharing for subcontractors.
- Production offline priming for multiple Locations.
- Internal technician Location cardinality.
- Serialized-product lifecycle and Asset scope.
- Same-intervention reusable-material turnaround.
- Destination acceptance for ProductTransfer.
- Scrap ProcessingPlan.
- Final pause reasons and TE/TEC effects.
- Work Type checklist/evidence catalogue.
- PHC contracts, authentication and reconciliation.
- Analytic-centre derivation.
- Exact-coordinate contract.
- Auto import/reconciliation scope.
- RRT/IDR2 integration.
- Licensing and sharing.
- Evidence retention and migration.
- Production package/mobile/manual configuration.

# 20. Known Constraints and Risks

- No global design sign-off was evidenced.
- Much repository implementation was AI-assisted and may be exploratory.
- Repository metadata may not match any deployed org.
- Current Close Flow conflicts with the desired lifecycle separation.
- Current Return Flow is incomplete for production reverse logistics.
- `SC_FS_SLA_OT__mdt` contains org-specific IDs.
- PNI snapshots can lose transient transitions.
- NetGuard is read-only and creates dual entry.
- Exact intervention coordinates are unavailable.
- Multiple inventory Location visibility is proven, but shared ownership, sharing, offline priming and reconciliation are not.
- Crew-based stock inheritance is not established by the multiple-Location PoC.
- Offline stock conflicts can produce temporary divergence.
- PHC balance snapshots require watermark and replay protection.
- Same-intervention reuse may be too slow.
- Catalogue cleanup, alias governance and serial source remain dependencies.
- Rich media creates storage, sync and retention risk.
- January 2027 is a historical target, not a commitment without an approved baseline.
- CRM and Field Service share the org; unrelated CRM metadata must not be changed casually.

# 21. Current PoC / Demo Functionality

Present in local source or supported by PoC evidence:

- NOS API polling, mapping and Work Order upsert.
- Manual PNI file import.
- Integration batch/error monitoring.
- Cell extraction and confirmation fields.
- Cell-to-territory/technology/coordinate propagation.
- Work Order context mirrored to Service Appointment.
- Mobile Start OT.
- Mobile Close OT.
- Mobile Return Material.
- Pause interval recording.
- TE/TEC milestone implementation.
- SLA risk/breach automation.
- Resource Absence availability test.
- Crew-owned inventory test.
- Android multiple-inventory-Location selection using `ENABLE_MULTIPLE_LOCATIONS`.
- Dispatcher-oriented list views and field sets.

Still unapproved or unproven:

- Final shared subcontractor stock pattern.
- Production sharing for multiple Locations.
- Production offline priming.
- Serialized scan/offline consumption.
- Last-unit and concurrent-consumption conflict handling.
- PHC end-to-end integration.
- Same-intervention reuse.
- Autos import.
- RRT/IDR2 integration.
- Exact NOS coordinates.
- Production offline photo/evidence behaviour.
- Production Entitlement/mobile configuration.

# 22. Important Salesforce Metadata / Naming

Repository conventions:

- Project prefix: `SC_`.
- Field Service prefix: frequently `SC_FS_`.
- NOS integration classes: `SC_Nos*`.
- PNI ingestion classes: `SC_Pni*`.
- Mobile Flows use Portuguese labels and Salesforce API names.

Important metadata:

- `Lote_Integracao__c`
- `Ocorrencia_Integracao__c`
- `WorkOrder.Referencia_Ordem_Cliente__c`
- `WorkOrder.Estado_Cliente__c`
- `WorkOrder.Estado_Aceitacao_Cliente__c`
- `WorkOrder.Estado_Facturacao__c`
- `ServiceAppointment.Ordem__c`
- `WorkOrder.Celula__c`
- `ServiceAppointment.Celula_Codigo__c`
- `Data_Atribuicao_Cliente__c`
- `Data_Fecho_Tecnico__c`
- `Data_Producao__c`
- `Data_Entrega_Cadastro__c`
- `SC_FS_SLA_OT__mdt`
- `TE (intervenção)`
- `TEC (cadastro)`
- `SC_NOS_FFM_API`
- `SC_NOS_FFM_Cred`
- `SC_FS_Importar_PNI`

Preserve existing naming conventions, but do not assume that existing names or descriptions represent approved business terminology.

# 23. Items That Must Not Be Assumed

A coding agent must not assume that:

- This file contains decisions made after its Last consolidated date.
- This file is evidence that a decision was approved.
- Google Drive will always be accessible.
- The repository is synchronized with Drive.
- Local metadata is deployed or active.
- Repository implementation is formally approved.
- AI-generated implementation is decision evidence.
- Metadata descriptions are client-approved rules.
- A technically working PoC is production architecture.
- Work Order completion equals Service Appointment completion.
- NetGuard status equals internal execution state.
- `WORK_IN_PROGRESS` is the actual technician start.
- PNI absence means “without cadastro”.
- `Concluído Remunerado` means invoiced.
- PHC has a Work Order commercial entity.
- PHC integration already exists.
- Hourly polling solves same-intervention reuse.
- Scrap exists as Salesforce inventory.
- Reusable returns immediately increase Salesforce stock.
- Reusable A-references are aliases.
- Service Crew membership grants access to company stock.
- The successful multiple-Location PoC proves shared subcontractor inventory.
- `ENABLE_MULTIPLE_LOCATIONS` proves production sharing or offline priming.
- Parent/direct-child Location visibility determines stock ownership.
- Every technician owns individual stock.
- Every item has a barcode or serial.
- Every job consumes material.
- Every Work Type has an approved checklist.
- Work Step is independently assignable work.
- Estimated Duration is SLA.
- Generic Pending pauses TE or TEC.
- Operating Hours are the contractual SLA calendar.
- Six provisional zones are final.
- Geographic adjacency overrides skills.
- Cell coordinates are exact.
- External assignment should automatically create AssignedResource.
- Claim/release is approved.
- Optimization is in MVP.
- Standard photo capture covers rich annotation.
- RRT can be replaced with mass manual Work Orders.
- Auto source files have a stable format.
- Custom Metadata containing record IDs is portable.
- Permission-set presence proves end-to-end access.
- The full legacy evidence estate will be migrated.
- Any SinalCabo-specific design is a general Salesforce Field Service rule.

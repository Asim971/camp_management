# 1. Feature Name

Configuration Catalog and Versioned Drafting

## 2. Epic

- [Parent Epic: Configuration, Audit and Policy Administration](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 5, 10 and 13

## 3. Goal

**Problem:** Thresholds, windows, reason codes, notices and retention settings affect live workflows, but scattered constants cannot be reviewed, compared or reproduced historically. Some values are too sensitive for ordinary admins.

**Solution:** Provide a typed configuration catalog with scoped draft versions, schema validation, effective dates, dependencies and masking.

**Impact:** Policy changes become understandable and reproducible before activation.

## 4. User Personas

- Org/BMD admin, policy owner, privacy/security admin and auditor.

## 5. User Stories

- As an admin, I want settings grouped by policy domain so that I can find the right control.
- As a policy owner, I want drafts and diffs so that changes are reviewed before affecting users.
- As an auditor, I want the effective version for a historical event so that behavior is reproducible.
- As a restricted admin, I want secret/threshold values masked from ordinary roles.

## 6. Requirements

### Functional Requirements

- Catalog typed settings for campaign rules, attendance windows, reasons, quality/integrity thresholds, notices, retention and integrations.
- Show owner, scope, value type, sensitivity, current version, effective period and dependency/impact summary.
- Create immutable draft versions from current or selected prior version.
- Validate type, range, referential dependencies, language parity, overlapping effective dates and prohibited combinations.
- Provide field-level diff and impacted workflow/cohort preview.
- Mask restricted values and show only metadata to unauthorized admins.
- Support organization/global inheritance with explicit override source.
- Resolve and record the effective configuration version for governed business events.

### Non-Functional Requirements

- Enforce schema and field-level permissions server-side.
- Never expose secrets in UI, logs, URLs or audit values.
- Keep versions immutable and reproducible.
- Meet accessible form, diff and error-summary requirements.

## 7. Acceptance Criteria

- **Given** an invalid threshold/range, **when** a draft is saved, **then** validation identifies the field and no activation-ready version results.
- **Given** an ordinary admin views a restricted setting, **when** catalog loads, **then** its existence/owner may show but value remains masked.
- **Given** organization override, **when** effective value is viewed, **then** inherited and override sources are explicit.
- **Given** a historical attendance event, **when** audited, **then** its effective configuration version can be resolved.
- **Given** a bilingual notice missing one language, **when** draft validation runs, **then** submission for approval is blocked.

## 8. Out of Scope

- Activation/approval decisions and direct secret retrieval.
- Arbitrary code deployment through configuration.

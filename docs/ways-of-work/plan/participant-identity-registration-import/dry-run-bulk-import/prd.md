# 1. Feature Name

Dry-Run and Idempotent Bulk Registration Import

## 2. Epic

- [Parent Epic: Participant Identity, Registration and Bulk Import](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 10, 11 and 14

## 3. Goal

**Problem:** Large participant files can contain duplicates, unauthorized rows, missing profiles and format errors. A one-step import or generic failure message makes correction unsafe and replay can duplicate registrations.

**Solution:** Provide template-controlled upload, scanning, non-mutating dry run, row-level outcomes and explicit idempotent commit of confirmed rows.

**Impact:** Administrators process large audiences efficiently with explainable and reconcilable results.

## 4. User Personas

- Campaign admin with bulk permission, data operator and support/auditor.

## 5. User Stories

- As an admin, I want an approved template and dry run so that I can fix data before mutation.
- As an admin, I want every row classified with corrective action so that partial failures are understandable.
- As an admin, I want to commit only confirmed valid rows so that warnings/errors do not slip through.
- As an operator, I want safe retry and reconciliation so that replay cannot duplicate registrations.

## 6. Requirements

### Functional Requirements

- Provide a versioned template with stable row ID and field guidance.
- Validate file type/size/schema and malware-scan before processing.
- Run asynchronous dry run without creating registrations.
- Classify rows as valid, warning, duplicate, needs profile, unauthorized or error with reason and matched ID where allowed.
- Show summary counts, filters, row detail and masked downloadable result.
- Require explicit confirmation of rows eligible for commit.
- Commit with job idempotency key and deterministic row identity.
- Support Processing, Completed, Partially completed, Failed and Cancelled lifecycle with progress.
- Retry only eligible failed rows and reconcile each committed row to registration/request.
- Preserve job, input version, configuration version and row outcomes in audit.

### Non-Functional Requirements

- Process files asynchronously above the agreed threshold without blocking UI.
- Enforce permission/scope per row server-side.
- Mask sensitive values in UI/results and expire source/result downloads.
- Ensure replay creates zero duplicate registrations.
- Provide accessible virtualized row tables and exact failure recovery.

## 7. Acceptance Criteria

- **Given** a mixed-quality file, **when** dry run completes, **then** every row has one stable outcome and no registration exists yet.
- **Given** unauthorized rows, **when** results display, **then** they cannot be selected for commit and restricted identity data is masked.
- **Given** confirmed valid rows, **when** commit is retried with the same key, **then** each row is registered at most once.
- **Given** partial server failure, **when** the job completes, **then** successful and failed rows remain distinguishable and only eligible failures can retry.
- **Given** a malformed or unsafe file, **when** uploaded, **then** processing stops with a specific safe error and no row mutation.

## 8. Out of Scope

- Spreadsheet editing inside the product.
- Automatic creation/merge of missing authoritative profiles.
- Mobile file upload in MVP.
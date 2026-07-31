# 1. Feature Name

Authoritative Carpenter Identity Overview

## 2. Epic

- [Parent Epic: Carpenter 360 Engagement and Commercial History](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 5, 10 and 12

## 3. Goal

**Problem:** Campaign users need a trustworthy participant overview but must not create a competing customer master or expose sensitive identity data. Source latency and conflicting labels can make a composite profile misleading.

**Solution:** Provide a read-only, Sales Eco-anchored identity header with masked contact cues, source/freshness labels and governed navigation to engagement history.

**Impact:** Users confirm the right carpenter quickly while master-data ownership remains intact.

## 4. User Personas

- Campaign admin, CRM reviewer, manager and authorized support user.

## 5. User Stories

- As a user, I want the authoritative ID and multiple identity cues so that I know I opened the correct person.
- As a privacy-conscious user, I want phone and NID masked so that unnecessary personal data is not exposed.
- As a user, I want source and freshness labels so that I can judge stale details correctly.
- As a data steward, I want corrections routed to Sales Eco so that no shadow master develops.

## 6. Requirements

### Functional Requirements

- Resolve profiles by authoritative Sales Eco carpenter ID within role and territory scope.
- Show permitted name, profile image, carpenter ID, masked phone, territory/dealer, segment/status and source freshness.
- Identify source-controlled fields and route correction requests to the authoritative workflow.
- Show summary counts for campaigns, approved attendance and attributable commercial activity with as-of dates.
- Distinguish unavailable, delayed, stale and restricted fields from true empty values.
- Link to campaign timeline and commercial history while preserving scope.
- Audit sensitive profile access according to role and policy.
- Do not permit local mutation or storage of a competing master record.

### Non-Functional Requirements

- Enforce field-level authorization server-side and mask sensitive values in URLs/logs.
- Meet responsive, keyboard and screen-reader requirements.
- Show profile freshness and partial-source status without blocking available safe content.
- Keep source IDs stable across downstream views.

## 7. Acceptance Criteria

- **Given** an authorized ID, **when** the overview opens, **then** authoritative identity cues and source freshness are visible.
- **Given** a stale source field, **when** rendered, **then** it is labeled stale rather than silently presented as current.
- **Given** a user without sensitive-field permission, **when** the profile loads, **then** full phone/NID and restricted data are absent.
- **Given** a requested identity correction, **when** action is selected, **then** it routes to Sales Eco stewardship without editing the local profile.
- **Given** one source is unavailable, **when** the page loads, **then** available sections render and the affected summary is marked unavailable.

## 8. Out of Scope

- Master-profile creation, merge or direct editing.
- Evidence review and unrestricted identity export.

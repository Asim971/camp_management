# 1. Feature Name

Bilingual Localization and Versioned Notices

## 2. Epic

- [Parent Epic: Shared Sales Ecosystem Experience and Trust Controls](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), especially sections 12 and 13

## 3. Goal

**Problem:** Field and office users require Bangla and English, while critical purpose notices must prove exactly what language and version a participant received. Hardcoded translations drift and cannot support legal traceability. Bangla expansion can also break compact layouts.

**Solution:** Provide centralized ARB-based localization plus versioned bilingual notice content with explicit language choice, parity review and persisted presentation outcomes.

**Impact:** Users receive understandable, consistent language and the organization can demonstrate which approved notice governed each capture.

## 4. User Personas

- Field users and campaign participants using Bangla or English.
- Office users using localized labels and errors.
- Legal, privacy, product and auditors governing notices.

## 5. User Stories

- As a participant, I want to choose notice language before acceptance so that I understand the purpose and consequences.
- As a field user, I want direct localized guidance so that I can correct errors without losing work.
- As an auditor, I want notice version, language, time and outcome so that consent evidence is reconstructable.
- As a content owner, I want approved language pairs versioned together so that translations cannot drift silently.

## 6. Requirements

### Functional Requirements

- Support English and Bangla application strings through generated localization resources.
- Use Inter with Noto Sans Bengali fallback and equivalent hierarchy/line height.
- Store critical notice content as versioned objects rather than hardcoded UI strings.
- Require explicit language selection before presenting acceptance controls.
- Keep purpose, data used, provider category, retention, rights/contact and refusal consequence semantically equivalent.
- Record notice ID/version, language, presented timestamp and acceptance/refusal/manual-route outcome.
- Separate optional marketing communication consent from attendance identity verification.
- Prevent activation of a notice version missing an approved language variant.
- Preserve prior versions for historical rendering and audit.

### Non-Functional Requirements

- Test supported layouts for Bangla wrapping at 320 px and 200% web zoom.
- Meet screen-reader language, reading-order and accessible-name requirements.
- Use server-authoritative notice versions and timestamps for committed records.
- Cache only approved active notice content needed for offline sessions.

## 7. Acceptance Criteria

- **Given** a participant selects Bangla, **when** the notice opens, **then** all required sections and actions appear in approved Bangla before acceptance.
- **Given** an attendance record, **when** audited, **then** its notice version, language, timestamp and outcome are available.
- **Given** a draft notice lacks one approved language, **when** activation is attempted, **then** activation is blocked with a specific reason.
- **Given** an offline assigned session, **when** the active notice is required, **then** the approved cached version is available and the outcome syncs later.
- **Given** long Bangla content on a small device, **when** rendered, **then** no required text or action is clipped.

## 8. Out of Scope

- Machine translation or unreviewed language generation.
- Legal approval of notice wording itself.
- Languages other than English and Bangla in MVP.

# 1. Feature Name

BMD Design System and Controlled Status Vocabulary

## 2. Epic

- [Parent Epic: Shared Sales Ecosystem Experience and Trust Controls](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), especially sections 8 and 11

## 3. Goal

**Problem:** Inconsistent components and synonyms for the same state make cross-surface workflows difficult to reconcile. Brand red can also be confused with errors when component semantics are not controlled. Dense tables and operational states need reusable behavior, not page-specific conventions.

**Solution:** Provide BMD-themed Material 3 tokens and reusable Flutter components with typed campaign, registration, attendance, import and integrity states rendered through one vocabulary.

**Impact:** Screens remain visually and semantically consistent, implementation duplication falls, and status-based reporting reconciles across mobile, CRM and analytics.

## 4. User Personas

- All product users consuming statuses and actions.
- Designers, engineers and QA maintaining cross-surface consistency.

## 5. User Stories

- As a user, I want the same record state to use the same words everywhere so that I understand its current position.
- As a keyboard or screen-reader user, I want status conveyed by text and semantics so that color is never the only signal.
- As an engineer, I want typed components so that a feature cannot invent unsupported states or styling.
- As an operations user, I want dense tables to preserve the identity column and next action so that large queues remain usable.

## 6. Requirements

### Functional Requirements

- Implement typed BMD color, typography, spacing, radius and elevation tokens.
- Provide one `StatusChip` renderer for controlled campaign, registration, attendance, import and integrity enums.
- Render every status with label and icon; prohibit raw status strings in feature UI.
- Provide button, field, search, table, KPI, exception-card, dialog, side-sheet, bottom-sheet and evidence primitives.
- Reserve filled brand red for the primary action, selected navigation and one principal chart series.
- Use distinct semantic success, warning, error and information tones.
- Enforce one filled primary action per screen or step in development checks.
- Provide virtualized tables with sticky headers/identity columns and safe bulk selection.
- Publish component states for default, hover, focus, pressed, disabled, loading, error and empty.

### Non-Functional Requirements

- Meet contrast requirements and never encode meaning by color alone.
- Maintain token parity between design CSS and Flutter theme values.
- Support English and Bangla expansion without clipping.
- Keep standard web rows at 44-48 px and field targets at least 48 x 48 px.
- Provide golden/semantic regression tests for controlled components and statuses.

## 7. Acceptance Criteria

- **Given** one attendance record, **when** rendered in mobile queue, CRM and analytics, **then** its controlled status label and semantic meaning are identical.
- **Given** any status chip, **when** color perception is unavailable, **then** icon and text still communicate the state.
- **Given** a feature attempts an unsupported raw status, **when** it is compiled/tested, **then** the typed API prevents or flags the usage.
- **Given** a table exceeding the viewport, **when** scrolled, **then** the header and identifying column remain available.
- **Given** Bangla labels and 200% zoom, **when** components render, **then** text does not clip or conceal critical actions.

## 8. Out of Scope

- Page-specific business workflows.
- A new campaign brand or unapproved design tokens.
- Domain-specific chart calculations.

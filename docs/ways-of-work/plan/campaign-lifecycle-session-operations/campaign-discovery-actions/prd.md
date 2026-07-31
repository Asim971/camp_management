# 1. Feature Name

Campaign Discovery and Permitted Actions

## 2. Epic

- [Parent Epic: Campaign Lifecycle and Session Operations](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 5, 7 and 11

## 3. Goal

**Problem:** Users cannot manage campaigns efficiently if returned, blocked or upcoming work is buried in alphabetical lists. Actions also vary by lifecycle, role and scope, creating risk when unavailable actions appear executable.

**Solution:** Provide a scoped, searchable campaign list with exception-first ordering, visible lifecycle/next action and permission-aware commands.

**Impact:** Users find actionable campaigns faster and invalid lifecycle operations decline.

## 4. User Personas

- Campaign creators/admins, approvers and management viewers.

## 5. User Stories

- As an admin, I want returned and active-exception campaigns first so that I address urgent work.
- As a creator, I want search and filters so that I can find campaigns by name, code, owner or territory.
- As a user, I want only valid permitted actions so that I do not attempt prohibited transitions.
- As a mobile viewer, I want compact campaign cards so that status and next action remain readable.

## 6. Requirements

### Functional Requirements

- List only campaigns within role and organization/territory scope.
- Search campaign name/code and support high-value status, owner, territory, type and date filters.
- Default-sort active exceptions, returned and upcoming campaigns before ordinary records.
- Show campaign, type, owner, territory, dates/sessions, status, target, verified attendance, approval/SLA and next action.
- Provide row/detail navigation and permitted edit draft, submit, duplicate/template, cancel and view actions.
- Re-evaluate actions after lifecycle or permission changes and explain unavailable commands.
- Preserve filters in navigation/session and provide removable active-filter indicators.
- Render a read-only mobile card variant without losing status or next action.

### Non-Functional Requirements

- Use virtualized accessible tables and server-side scoped filtering for large datasets.
- Return initial actionable results within the agreed list performance target.
- Never disclose out-of-scope campaign existence through counts or search.
- Show loading, empty, delayed, partial and permission-denied states.

## 7. Acceptance Criteria

- **Given** returned and ordinary campaigns, **when** the default list loads, **then** returned/actionable records appear first.
- **Given** a creator without cancel permission, **when** row actions open, **then** cancel is absent or disabled with no executable endpoint access.
- **Given** search and filters, **when** navigating to detail and back, **then** the list context is preserved.
- **Given** an out-of-scope campaign code, **when** searched, **then** no identifying result or count is disclosed.
- **Given** mobile width, **when** cards render, **then** name, date, status, target/verified and next action remain visible.

## 8. Out of Scope

- Campaign authoring forms, approval decisions or session activation.
- Analytics dashboard aggregation.

# 1. Feature Name

Adaptive Sales Ecosystem Shell and Scoped Access

## 2. Epic

- [Parent Epic: Shared Sales Ecosystem Experience and Trust Controls](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), especially sections 3, 4 and 7

## 3. Goal

**Problem:** Users work across mobile field, web administration, CRM and analytics, but must not encounter a second navigation model or data outside their organization and territory scope. Client-only hiding is insufficient because deep links and stale sessions can still expose protected routes. Narrow viewports must retain critical status and privacy context.

**Solution:** Extend the Sales Ecosystem shell with adaptive navigation and route-level role/scope guards backed by server authorization. Preserve organization context, deep-link behavior and the correct navigation priority at every supported breakpoint.

**Impact:** Users reach relevant work faster while unauthorized modules, routes and data remain inaccessible.

## 4. User Personas

- Campaign creators, approvers, field users, CRM reviewers, admins and reporting viewers.
- Support users diagnosing access without receiving protected business data.

## 5. User Stories

- As an authenticated user, I want navigation limited to my role and scope so that I cannot enter irrelevant or prohibited modules.
- As a field user, I want an active-session-focused mobile shell so that attendance work is not interrupted by organization switching.
- As a web user, I want deep links and browser history to work so that I can return to authorized records directly.
- As a user whose access changed, I want a clear denial or redirect so that no protected content flashes before enforcement.

## 6. Requirements

### Functional Requirements

- Integrate the existing Sales Ecosystem session, organization and role context.
- Enforce role plus organization/territory scope before route construction and on every server request.
- Provide desktop drawer, tablet rail and mobile navigation with no more than four field destinations.
- Preserve breadcrumbs, page title, environment/context indicator and user actions on web.
- Route active field users to the assigned session and hide context switchers during capture.
- Support authorized deep links, refresh and back/forward navigation without personal data or media tokens in URLs.
- Show permission-denied, expired-session and out-of-scope states without disclosing record details.
- Re-evaluate routes when session, role or organization scope changes.

### Non-Functional Requirements

- Block protected content before first render and recheck authorization server-side.
- Support 320 px through large desktop layouts without hiding sync, privacy or SLA warnings.
- Meet WCAG 2.2 AA focus order, landmarks, labels and keyboard navigation requirements.
- Avoid storing sensitive route parameters in browser history, analytics or logs.

## 7. Acceptance Criteria

- **Given** a user without Campaign Approval permission, **when** they navigate directly to an approval URL, **then** no campaign data renders and an access-denied destination is shown.
- **Given** a field user with one active assigned session, **when** the app opens, **then** the session-focused home is primary and organization switching is absent from capture paths.
- **Given** an authorized web deep link, **when** the browser refreshes, **then** the same scoped page reloads after authentication.
- **Given** a role or territory change during a session, **when** access is refreshed, **then** prohibited routes are removed and any open prohibited route exits without a data flash.
- **Given** each supported breakpoint, **when** shell navigation is rendered, **then** current status, primary action and mandatory warnings remain reachable and non-overlapping.

## 8. Out of Scope

- Replacing the enterprise identity provider or defining role assignments.
- Business rules for campaign, verification or analytics actions.
- A standalone campaign navigation hierarchy.

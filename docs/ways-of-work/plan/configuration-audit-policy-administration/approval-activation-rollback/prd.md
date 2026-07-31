# 1. Feature Name

Configuration Approval, Activation and Rollback

## 2. Epic

- [Parent Epic: Configuration, Audit and Policy Administration](../epic.md)
- [Flutter Architecture Plan](../../../../../ARCHITECTURE_Flutter.md), sections 6, 10 and 14

## 3. Goal

**Problem:** Valid configuration can still be risky if activated without independent review, timing controls or rollback. In-flight sessions and historical decisions must retain the version that governed them.

**Solution:** Apply segregation-of-duties approval, scheduled activation, immutable effective versions, impact monitoring and governed rollback.

**Impact:** Policy changes reach production deliberately and can be reversed without rewriting history.

## 4. User Personas

- Configuration requester, independent approver, policy owner and operations supervisor.

## 5. User Stories

- As an approver, I want diff, impact and warnings so that I can make an informed decision.
- As an operator, I want scheduled activation and status so that rollouts are predictable.
- As a policy owner, I want rollback to a known version so that harmful changes can be contained.
- As an auditor, I want in-flight events pinned to their original version so that history is stable.

## 6. Requirements

### Functional Requirements

- Submit validated drafts for approval with owner, rationale, impact and requested effective time.
- Enforce configured segregation of duties and role/scope.
- Support Approve, Return and Reject with mandatory reason/acknowledgements.
- Activate immediately or at an approved future time using server-authoritative time.
- Prevent overlapping incompatible effective versions.
- Pin governed events/sessions to the resolved version according to policy; never retroactively rewrite completed decisions.
- Monitor activation result and affected service/config propagation.
- Roll back by activating a new version based on a prior known version, with reason/approval requirements.
- Notify stakeholders after commit and separate delivery failure from policy state.

### Non-Functional Requirements

- Use optimistic concurrency and idempotent transitions.
- Maintain immutable approval, activation and rollback lineage.
- Fail closed for high-risk activation when propagation/audit commitment cannot be verified.
- Meet accessible diff, warning and confirmation behavior.

## 7. Acceptance Criteria

- **Given** requester equals approver under SoD policy, **when** approval is attempted, **then** the decision is blocked.
- **Given** an approved future activation, **when** server time reaches it, **then** one effective version activates and status is audited.
- **Given** an in-flight session pinned to a prior version, **when** a new version activates, **then** the session continues under the documented pinning rule.
- **Given** rollback, **when** approved and activated, **then** a new effective version is created while prior history remains unchanged.
- **Given** notification fails after activation, **when** status is viewed, **then** activation remains committed and delivery failure is separate.

## 8. Out of Scope

- Editing configuration values inside approval.
- Rewriting historical business outcomes or bypassing emergency governance policy.

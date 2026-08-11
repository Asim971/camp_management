/// Migrations, embedded as source. Keyed by id; applied in lexical order.
const Map<String, String> embeddedMigrations = {
  '001_foundation': _foundation,
  '002_idempotency_reservations': _idempotencyReservations,
};

const String _foundation = r'''
CREATE TABLE organizations (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE territories (
  id               TEXT PRIMARY KEY,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  name             TEXT NOT NULL
);

CREATE TABLE staff_users (
  id               TEXT PRIMARY KEY,
  username         TEXT NOT NULL UNIQUE,
  display_name     TEXT NOT NULL,
  password_hash    TEXT NOT NULL,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  is_active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Roles and territories are rows, not arrays: sub-project 7 administers them
-- individually and must audit each grant.
CREATE TABLE staff_user_roles (
  user_id  TEXT NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  role     TEXT NOT NULL,
  PRIMARY KEY (user_id, role)
);

CREATE TABLE staff_user_territories (
  user_id       TEXT NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  territory_id  TEXT NOT NULL REFERENCES territories(id),
  PRIMARY KEY (user_id, territory_id)
);

-- family_id groups a rotation chain. Presenting an already-rotated token
-- revokes the whole family: the standard stolen-refresh-token defence.
CREATE TABLE refresh_tokens (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  family_id   TEXT NOT NULL,
  token_hash  TEXT NOT NULL UNIQUE,
  issued_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL,
  used_at     TIMESTAMPTZ,
  revoked_at  TIMESTAMPTZ
);
CREATE INDEX refresh_tokens_family_idx ON refresh_tokens(family_id);

CREATE TABLE campaigns (
  id                TEXT PRIMARY KEY,
  organization_id   TEXT NOT NULL REFERENCES organizations(id),
  name              TEXT NOT NULL,
  type              TEXT NOT NULL,
  objective         TEXT,
  status            TEXT NOT NULL,
  owner_id          TEXT NOT NULL REFERENCES staff_users(id),
  approver_id       TEXT REFERENCES staff_users(id),
  start_at          TIMESTAMPTZ,
  end_at            TIMESTAMPTZ,
  venue             TEXT,
  target_audience   INTEGER NOT NULL DEFAULT 0,
  budget_reference  TEXT,
  geofence_enabled  BOOLEAN NOT NULL DEFAULT FALSE,
  -- Bumped on every mutation. The conflict check is
  -- "WHERE id = @id AND version = @version" returning zero rows, so a code
  -- path that forgets to compare cannot silently overwrite.
  version           INTEGER NOT NULL DEFAULT 1,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX campaigns_org_status_idx ON campaigns(organization_id, status);
CREATE INDEX campaigns_name_idx ON campaigns(lower(name));

CREATE TABLE campaign_territories (
  campaign_id   TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  territory_id  TEXT NOT NULL REFERENCES territories(id),
  PRIMARY KEY (campaign_id, territory_id)
);

CREATE TABLE campaign_sessions (
  id           TEXT PRIMARY KEY,
  campaign_id  TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  venue        TEXT,
  capacity     INTEGER,
  start_at     TIMESTAMPTZ,
  end_at       TIMESTAMPTZ,
  status       TEXT NOT NULL DEFAULT 'PLANNED'
);
CREATE INDEX campaign_sessions_campaign_idx ON campaign_sessions(campaign_id);

-- Immutable snapshot per submit. Without it a resubmission has nothing to diff
-- against, and sub-project 3's changed-field view becomes unimplementable
-- after the fact.
CREATE TABLE campaign_submissions (
  id            TEXT PRIMARY KEY,
  campaign_id   TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  version       INTEGER NOT NULL,
  submitted_by  TEXT NOT NULL REFERENCES staff_users(id),
  submitted_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  snapshot      JSONB NOT NULL
);
CREATE INDEX campaign_submissions_campaign_idx
  ON campaign_submissions(campaign_id, submitted_at DESC);

-- Exactly what the approval PRD requires recorded: reviewer, decision, reason,
-- warning acknowledgements, version, time and correlation id.
CREATE TABLE campaign_decisions (
  id                     TEXT PRIMARY KEY,
  campaign_id            TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  submission_id          TEXT REFERENCES campaign_submissions(id),
  reviewer_id            TEXT NOT NULL REFERENCES staff_users(id),
  decision               TEXT NOT NULL,
  reason                 TEXT,
  acknowledged_warnings  JSONB NOT NULL DEFAULT '[]'::jsonb,
  version_at_decision    INTEGER NOT NULL,
  correlation_id         TEXT,
  decided_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX campaign_decisions_campaign_idx ON campaign_decisions(campaign_id);

-- Scoped per user so one user's key cannot replay another's response.
-- request_hash guards a key reused with a different body.
CREATE TABLE idempotency_keys (
  key              TEXT NOT NULL,
  user_id          TEXT NOT NULL REFERENCES staff_users(id) ON DELETE CASCADE,
  request_hash     TEXT NOT NULL,
  response_status  INTEGER NOT NULL,
  response_body    TEXT NOT NULL,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at       TIMESTAMPTZ NOT NULL,
  PRIMARY KEY (user_id, key)
);

CREATE TABLE audit_events (
  id              TEXT PRIMARY KEY,
  actor_id        TEXT,
  action          TEXT NOT NULL,
  resource_type   TEXT NOT NULL,
  resource_id     TEXT,
  correlation_id  TEXT,
  payload         JSONB NOT NULL DEFAULT '{}'::jsonb,
  occurred_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_events_resource_idx
  ON audit_events(resource_type, resource_id, occurred_at DESC);

CREATE TABLE app_config (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enforced by default: a missing or unreadable config row must not silently
-- disable a governance control (spec section 6).
INSERT INTO app_config (key, value) VALUES ('sod.enforced', 'true');
''';

// A NULL response_status/response_body marks a row as a *reservation*:
// someone has claimed this (user_id, key) and is executing the request right
// now, no response yet exists to replay. Without this, the middleware could
// only tell "never seen this key" from "seen it, here's the answer" — with
// no way to say "seen it, still running", which is exactly the state a
// second concurrent request needs to distinguish (spec's idempotency
// fix-round: two concurrent identical POSTs must not both run the handler).
const String _idempotencyReservations = r'''
ALTER TABLE idempotency_keys ALTER COLUMN response_status DROP NOT NULL;
ALTER TABLE idempotency_keys ALTER COLUMN response_body DROP NOT NULL;
''';

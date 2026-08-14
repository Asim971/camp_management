/// Migrations, embedded as source. Keyed by id; applied in lexical order.
const Map<String, String> embeddedMigrations = {
  '001_foundation': _foundation,
  '002_idempotency_reservations': _idempotencyReservations,
  '003_role_check': _roleCheck,
  '004_identity': _identity,
  '005_imports': _imports,
  '006_session_status': _sessionStatus,
  '007_attendance': _attendance,
  '008_verification': _verification,
  '009_escalation': _escalation,
  '010_queue_indexes': _queueIndexes,
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

/// An unknown role reaching the login response breaks sign-in at the
/// client's claims trust boundary (scope_claims.dart rejects unrecognised
/// names). The list below IS that vocabulary — change either only with the
/// other (slice-1 final review, deferred M10).
const String _roleCheck = r'''
ALTER TABLE staff_user_roles
  ADD CONSTRAINT staff_user_roles_role_check
  CHECK (role IN ('campaign_creator', 'marketing_approver', 'crm_verifier',
                  'crm_supervisor', 'field_user', 'admin',
                  'reporting_viewer'));
''';

const String _identity = r'''
CREATE TABLE carpenters (
  id               TEXT PRIMARY KEY,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  full_name        TEXT NOT NULL,
  -- Raw phone and nullable nid never leave the server unmasked (spec 2a.D2);
  -- they exist as sub-project 8's reconciliation join keys (D1).
  phone            TEXT NOT NULL,
  nid              TEXT,
  territory_id     TEXT REFERENCES territories(id),
  dealer_context   TEXT,
  thumbnail_url    TEXT,
  eligible         BOOLEAN NOT NULL DEFAULT TRUE,
  display_code     TEXT NOT NULL UNIQUE,
  source           TEXT NOT NULL,
  sync_status      TEXT NOT NULL DEFAULT 'LOCAL_ONLY',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX carpenters_org_name_idx
  ON carpenters(organization_id, lower(full_name));
CREATE INDEX carpenters_phone_idx ON carpenters(phone);
CREATE INDEX carpenters_nid_idx ON carpenters(nid);
-- Deliberately NO unique constraint on phone/nid: D1 matching is
-- confidence-scored with human adjudication (sub-project 8), and the schema
-- must tolerate what the matcher is designed to resolve (spec 2a.D3).

CREATE SEQUENCE carpenter_display_serial START 10000;

CREATE TABLE registrations (
  campaign_id    TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  carpenter_id   TEXT NOT NULL REFERENCES carpenters(id),
  status         TEXT NOT NULL,
  registered_by  TEXT NOT NULL REFERENCES staff_users(id),
  registered_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, carpenter_id)
);
CREATE INDEX registrations_carpenter_idx ON registrations(carpenter_id);

CREATE TABLE profile_requests (
  id            TEXT PRIMARY KEY,
  campaign_id   TEXT NOT NULL REFERENCES campaigns(id),
  carpenter_id  TEXT NOT NULL REFERENCES carpenters(id),
  requested_by  TEXT NOT NULL REFERENCES staff_users(id),
  name          TEXT NOT NULL,
  phone         TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'PENDING',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX profile_requests_campaign_idx ON profile_requests(campaign_id);
''';

const String _imports = r'''
CREATE TABLE import_jobs (
  id               TEXT PRIMARY KEY,
  campaign_id      TEXT NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  organization_id  TEXT NOT NULL REFERENCES organizations(id),
  status           TEXT NOT NULL,              -- ImportStatus wire value
  filename         TEXT NOT NULL,
  file_hash        TEXT NOT NULL,              -- sha256 of the bytes (2b.D3)
  total_rows       INTEGER NOT NULL DEFAULT 0,
  processed_rows   INTEGER NOT NULL DEFAULT 0,
  config_version   TEXT,
  uploaded_by      TEXT NOT NULL REFERENCES staff_users(id),
  claimed_at       TIMESTAMPTZ,                -- worker start; reaper input (2b.D2)
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX import_jobs_campaign_idx ON import_jobs(campaign_id);
CREATE INDEX import_jobs_status_claimed_idx ON import_jobs(status, claimed_at);

CREATE TABLE import_job_rows (
  job_id               TEXT NOT NULL REFERENCES import_jobs(id) ON DELETE CASCADE,
  row_id               TEXT NOT NULL,          -- "row-<1-based line>" (2b.D4)
  name                 TEXT NOT NULL,
  phone                TEXT NOT NULL,          -- raw; never leaves the server (2a.D2)
  nid                  TEXT,
  territory_hint       TEXT,
  dealer_context       TEXT,
  outcome              TEXT,                   -- ImportRowOutcome, NULL until classified
  message              TEXT,
  linked_carpenter_id  TEXT REFERENCES carpenters(id),
  PRIMARY KEY (job_id, row_id)
);
''';

const String _sessionStatus = r'''
-- 3a reconciles the session vocabulary: the foundation shipped
-- campaign_sessions.status DEFAULT 'PLANNED', but the ratified SessionStatus
-- contract (campaign_contracts) has no PLANNED — a freshly created session is
-- UPCOMING. The wizard insert sets no status and leans on this default.
ALTER TABLE campaign_sessions ALTER COLUMN status SET DEFAULT 'UPCOMING';
UPDATE campaign_sessions SET status = 'UPCOMING' WHERE status = 'PLANNED';
''';

const String _attendance = r'''
CREATE TABLE consent_notices (
  version       INTEGER     NOT NULL,
  language      TEXT        NOT NULL,
  title         TEXT        NOT NULL,
  body          TEXT        NOT NULL,
  content_hash  TEXT        NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (version, language)
);

-- No organization_id: written by the bearer-less (signed) upload PUT, which
-- has no auth context. Org scope is enforced by the attendance row that links
-- it at confirm time (sub-project 4a.D2/D3). Real object storage, encryption
-- at rest and retention are sub-project 4b.
CREATE TABLE media_objects (
  id            TEXT PRIMARY KEY,
  content_type  TEXT        NOT NULL,
  bytes         BYTEA       NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE attendance (
  id              TEXT PRIMARY KEY,            -- == idempotency key == media id
  organization_id TEXT        NOT NULL REFERENCES organizations(id),
  campaign_id     TEXT        NOT NULL REFERENCES campaigns(id),
  session_id      TEXT        NOT NULL REFERENCES campaign_sessions(id),
  carpenter_id    TEXT        NOT NULL REFERENCES carpenters(id),
  media_ref       TEXT        NOT NULL,
  status          TEXT        NOT NULL,        -- 'MATCH_PROCESSING' in 4a
  captured_by     TEXT        NOT NULL REFERENCES staff_users(id),
  captured_at     TIMESTAMPTZ NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX attendance_org_session_idx
  ON attendance(organization_id, session_id);

CREATE TABLE consent_records (
  id             TEXT PRIMARY KEY,
  attendance_id  TEXT        NOT NULL REFERENCES attendance(id) ON DELETE CASCADE,
  notice_version INTEGER     NOT NULL,
  language       TEXT        NOT NULL,
  content_hash   TEXT        NOT NULL,
  shown_at       TIMESTAMPTZ NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
''';

const String _verification = r'''
ALTER TABLE attendance ADD COLUMN version               INTEGER NOT NULL DEFAULT 1;
ALTER TABLE attendance ADD COLUMN assignee_id           TEXT REFERENCES staff_users(id);
ALTER TABLE attendance ADD COLUMN machine_band          TEXT;   -- MatchBand wire; null before the machine check
ALTER TABLE attendance ADD COLUMN machine_reference_src TEXT;   -- ReferenceSource wire
ALTER TABLE attendance ADD COLUMN machine_reasons       JSONB NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX attendance_status_idx ON attendance(organization_id, status);

CREATE TABLE verification_decisions (
  id                   TEXT PRIMARY KEY,
  attendance_id        TEXT        NOT NULL REFERENCES attendance(id) ON DELETE CASCADE,
  verifier_id          TEXT        NOT NULL REFERENCES staff_users(id),
  outcome              TEXT        NOT NULL,
  reason               TEXT,
  supervisor_override  BOOLEAN     NOT NULL DEFAULT FALSE,
  version_at_decision  INTEGER     NOT NULL,
  correlation_id       TEXT,
  decided_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX verification_decisions_attendance_idx ON verification_decisions(attendance_id);
''';

const String _escalation = r'''
ALTER TABLE attendance ADD COLUMN escalated_at TIMESTAMPTZ;
ALTER TABLE attendance ADD COLUMN escalated_by TEXT REFERENCES staff_users(id);
''';

const String _queueIndexes = r'''
CREATE INDEX attendance_assignee_idx
  ON attendance(organization_id, status, assignee_id);
CREATE INDEX attendance_escalated_idx
  ON attendance(organization_id, status)
  WHERE escalated_at IS NOT NULL;
''';

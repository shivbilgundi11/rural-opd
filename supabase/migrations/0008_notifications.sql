-- Module 2 · Step 8 — Transactional outbox & delivery log
--
-- Module 10 issues a token and enqueues "your token is ready" in the *same*
-- transaction. If the transaction rolls back, the message was never enqueued; if
-- it commits, the message cannot be lost. Calling Expo Push inline instead would
-- mean either notifying a patient about a token that got rolled back, or losing
-- the notification when the push call fails after commit.
--
-- Module 13 owns the drain worker. This file owns the shape it drains.

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- notification_outbox
-- ---------------------------------------------------------------------------
create table notification_outbox (
  id              uuid primary key default gen_random_uuid(),
  -- What the message is about. Nullable because Module 14's follow-up reminders
  -- are not tied to a live appointment.
  appointment_id  uuid references appointments (id) on delete restrict,
  token_id        uuid references opd_tokens (id) on delete restrict,
  session_id      uuid references opd_sessions (id) on delete restrict,
  recipient_auth_user_id uuid references auth.users (id) on delete cascade,
  -- Template key plus its substitutions, never a rendered string: the patient's
  -- language is a read-time decision, and PRD §8 forbids parking a rendered
  -- clinical sentence in a queue table.
  template_key    text not null,
  payload         jsonb not null default '{}',
  channels        notification_channel[] not null default '{PUSH}'
                    check (array_length(channels, 1) >= 1),
  status          outbox_status not null default 'PENDING',
  attempts        integer not null default 0 check (attempts >= 0),
  next_attempt_at timestamptz not null default now(),
  last_error      text,
  -- The whole reason a retried transaction cannot enqueue the same message
  -- twice. Module 13 composes it from the event it is reacting to, e.g.
  -- 'token_ready:<token_id>'.
  dedupe_key      text not null unique,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  sent_at         timestamptz
);

create trigger notification_outbox_set_updated_at
  before update on notification_outbox
  for each row execute function set_updated_at();

-- ---------------------------------------------------------------------------
-- notification_deliveries
-- ---------------------------------------------------------------------------
-- One row per channel per attempt. Kept separate from the outbox so a retry
-- history does not overwrite itself: "we tried push twice, it failed, then SMS
-- worked" is the answer to a patient asking why they were not told.
create table notification_deliveries (
  id                bigserial primary key,
  outbox_id         uuid not null references notification_outbox (id) on delete restrict,
  channel           notification_channel not null,
  provider          text,
  provider_message_id text,
  succeeded         boolean not null,
  error_code        text,
  error_detail      text,
  attempted_at      timestamptz not null default now()
);

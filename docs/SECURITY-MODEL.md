# Security Model

Module 3. Who can see what, and why — written to be checked by someone who does
not read SQL.

The organising principle, stated once: **the database decides.** Not the mobile
app, not the staff web app, not an Edge Function. Both surfaces talk to the same
PostgREST endpoint with the same public key, so the only thing separating a
patient from another patient's medical history is a policy written here. A screen
that needs to hide something does not filter it — the policy hides it, and the
screen simply never receives it.

The corollary matters just as much for every module after this one: **no
client-side filtering substitutes for a policy.** If a list looks right only
because the app added a `where` clause, it is wrong.

---

## 1. The two locks

Everything below is enforced by two mechanisms that are easy to confuse and do
different jobs.

| Lock       | Controls                        | What it looks like when it stops you                       |
| ---------- | ------------------------------- | ---------------------------------------------------------- |
| **Grant**  | which _operations_ exist at all | a loud error: `42501 permission denied for table payments` |
| **Policy** | which _rows_ you may touch      | a quiet empty result, or an update that changes nothing    |

Both are needed, and picking the right one is a design decision rather than
taste.

"A receptionist cannot override a payment" is a **grant** problem. Nobody may
write `payments`, so there is no `UPDATE` grant on it for any signed-in user, and
an attempt fails with an error a developer will notice and a log will record.
Solving the same requirement with a policy would leave the operation available
and merely matching no rows — which looks exactly like a bug, gets a ticket
raised against it, and gets "fixed" by widening the predicate.

"A receptionist cannot read a medical profile" is a **policy** problem, because
`SELECT` on `medical_profiles` has to exist for patients. There the quiet empty
result is the correct answer.

`scripts/rls-attack-suite.sql` records which kind of denial each attack must
produce, and fails if one is ever swapped for the other.

### A fact that shapes everything

**There is no `patient` database role and no `receptionist` database role.**
PRD §2's five roles are _application_ roles, carried in `staff_profiles`. At the
database level a patient and a hospital admin are both the Postgres role
`authenticated`.

So a grant cannot tell them apart. Grants are the union of what any signed-in
user may ever do; policies narrow that to the individual. Where a column grant
appears — on `appointments`, `patients`, `opd_sessions` — it is the
_intersection_ of what every role needs, which is why those column lists are
short.

---

## 2. What each role can see

Reading guide: **own** means your own record plus family members explicitly
linked to your account. **hospital** means rows belonging to the hospital you
work at. A blank cell means no access of any kind.

| Table                     | Patient                  | Doctor                     | Receptionist                       | Hospital admin          | Super admin       |
| ------------------------- | ------------------------ | -------------------------- | ---------------------------------- | ----------------------- | ----------------- |
| `hospitals`               | read active              | read active + own          | read active + own                  | **manage own**          | **manage all**    |
| `doctors`                 | read active              | read active + own hospital | read own hospital                  | **manage own**          | **manage all**    |
| `opd_sessions`            | read bookable            | read own sessions          | read hospital                      | **manage own**          | **manage all**    |
| `staff_profiles`          | —                        | read self + colleagues     | read self + colleagues             | **manage own hospital** | **manage all**    |
| `patients`                | **manage own**           | read own queue             | read hospital + **register**       | read hospital           | read all          |
| `patient_family_links`    | **manage own**           | —                          | —                                  | —                       | read all          |
| `medical_profiles`        | **manage own**           | read _during consultation_ | —                                  | —                       | audited read only |
| `device_push_tokens`      | **manage own**           | —                          | —                                  | —                       | —                 |
| `appointments`            | read own, **cancel own** | read + update own sessions | read hospital, **book + check in** | read hospital           | read all          |
| `payments`                | read own                 | —                          | read hospital                      | read hospital           | read all          |
| `opd_tokens`              | read own                 | read own sessions          | read hospital                      | read hospital           | read all          |
| `queue_events`            | read own tokens          | read own sessions          | read hospital                      | read hospital           | read all          |
| `follow_ups`              | read own                 | read hospital              | read hospital                      | read hospital           | read all          |
| `notification_outbox`     | —                        | —                          | —                                  | —                       | read all          |
| `notification_deliveries` | —                        | —                          | —                                  | —                       | read all          |
| `audit_log`               | —                        | —                          | —                                  | —                       | read all          |
| `payment_webhook_events`  | —                        | —                          | —                                  | —                       | **—**             |

Two cells in that table are the ones worth arguing about, and both are
deliberate: a super admin **cannot** read a medical profile directly, and **no
one at all** can read `payment_webhook_events`. Sections 4 and 6 explain why.

### Nobody writes these

`payments`, `opd_tokens`, `queue_events` and `payment_webhook_events` have no
insert, update or delete permission for any signed-in user — not a patient, not
a receptionist, not the platform operator. They are written only by the server,
through functions invoked with the service key from Edge Functions (Modules 10
and 12).

That is what makes PRD §3.1's promise — _no token without a verified payment_ —
something the database enforces rather than something the application intends. A
token and its queue event are created in one transaction that also checks the
payment; there is no path that produces one without the others.

### Not signed in

An anonymous request reaches nothing. `anon` has no permission on any table.

Discovery is a signed-in experience in V1, so there is no anonymous surface to
design yet. If Module 7 decides a visitor should browse hospitals before signing
up, it opens exactly that one door, in the module that owns the decision, with a
test. Until then, a mistake in any policy here cannot leak to the open internet —
at worst it leaks to another signed-in user.

---

## 3. The patient rule (PRD §6.7)

> A patient can only read their own or explicitly linked family records.

Implemented in exactly one place — a function called
`patient_ids_for_current_user()` — which every patient-facing policy consults.
One definition, auditable in a single read, rather than fourteen policies to
compare for typos.

It returns two things and nothing else:

1. the patient record attached to your login;
2. patient records you hold an explicit **link** to.

**Creating a patient record does not grant access to it. Linking to it does.**

That distinction is the whole design. A receptionist registers walk-ins all day
and an account holder creates profiles for their children; neither act should by
itself hand over a clinical history. So the link row is the grant — and because
it is a row, deleting it is the revocation. Access ends the instant the link is
deleted, which the test suite proves by deleting one mid-test and re-reading.

### Why you cannot link yourself to a stranger

The obvious version of the rule — "you may create links you own" — is
catastrophic. A patient id is a bare identifier; anyone who learns or guesses one
would link themselves to it and read everything.

So creating a link requires **both**:

- the record must be one **you created** — provenance, not possession of an id;
- it must have **no login of its own** — a dependent, never another account
  holder.

Sharing records between two account holders would need consent from both. Nobody
has specified that feature, so it is refused rather than approximated. Four
separate attack tests sit on this one rule.

### The one thing a patient can change

A patient may cancel their own appointment (PRD PAT-18) and nothing else. Three
independent locks stand between a patient and the valuable forgery — marking
their own appointment as paid-and-ticketed:

1. **The column list.** A patient's update permission covers three columns:
   status, cancellation reason, cancellation time. The fee, the session and the
   patient are not in it, so no policy bug can expose them.
2. **The state machine.** Module 2's transition table has no legal move from a
   patient's starting state to "token generated".
3. **The policy.** The only status a patient may leave behind is "cancelled".

Which statuses a patient can cancel _from_ is not hardcoded here. The policy asks
Module 2's transition table, because PRD §10 lists the cancellation cut-off as an
open decision — so when the refund policy lands, widening it is a row in a
migration, visible in a diff, rather than an edit to a security policy.

Today that means a patient may cancel a booking that is awaiting payment, or one
waiting in the queue.

---

## 4. The doctor rule (PRD §2)

> Assigned hospital/session scope only.

A doctor sees the queue they are running: the tokens in their own sessions, the
patients holding them, and those patients' appointments. Not the hospital's other
clinics, and not the other hospital at all.

They see **no payments**. What a patient paid has no bearing on the consultation.

### Clinical access is bounded by time, not by role

A doctor can open a patient's medical profile **only while that patient is called
into, or sitting in, one of their own consultations.** It opens when they call the
patient and closes when the consultation completes.

The policy that almost gets written instead — "a doctor may read profiles of
patients at their hospital" — hands every doctor every chart in the building for
the whole day. That is the casual clinical browsing PRD §2 rules out, and no test
that only checks the allow case would catch it. So the suite calls a patient,
reads the chart, completes the consultation, and reads again expecting nothing.

Doctors have read access only. Recording clinical findings is an EMR feature and
PRD §1.2 puts EMR out of scope for V1.

---

## 5. The hospital boundary

A hospital admin manages their own hospital and cannot see another hospital's
appointments, payments, tokens, queue history, staff or patients.

**Catalogue data is the exception, and it is not a leak.** Hospitals, doctors and
sessions are the product's shop window — every patient browses them, because
discovery is the whole first step of the journey (PRD G1). So the admin of one
hospital can see that another hospital exists and what clinics it runs, exactly
as any patient can. Everything tenant-private is shut.

Two failure modes get their own tests, because they are the ones a reviewer skims
past:

- **Moving a row into another tenant.** Every administrative policy checks the
  row both on the way in and on the way out. Without the second check, an admin
  passes the test on their own doctor and then reassigns them to a hospital they
  do not administer — taking every session, appointment and token with them.
- **Minting a super admin.** A hospital admin can create staff at their own
  hospital and cannot create the one role whose reach is not hospital-bounded.

### The queue counters

`opd_sessions` is both catalogue configuration and live queue state, and the two
halves have different locks. Scheduling a clinic is administration. The
"now serving" number is the queue, and PRD §6.6 requires every queue change to be
auditable — so it is left out of the update permission entirely, for everyone.

Without that, a hospital admin could advance the number from a console, moving the
queue for every patient watching it, with nothing recorded about who did it or
why.

---

## 6. The super admin (PRD §2)

> Audited access; no casual clinical browsing.

Two requirements, and the second is what makes the first mean anything.

A super admin reads appointments, payments, tokens, queue history, the
notification queue and the audit log platform-wide — that is reconciliation and
support. They **cannot** read a medical profile directly. The only way in is a
function that writes an audit record and then returns the profile.

**Making the audited path the only path is the point.** Postgres cannot trigger
on a read, so "log it and trust everyone to use the wrapper" is not a control:
the direct read still works, and the person most able to route around the wrapper
is the one it exists to record. So the direct door is closed, and there is no
second one — no view exposes a clinical column either, which the suite asserts
rather than assumes.

The audit record says **that** a profile was read, by whom, and when. It does not
copy the allergies and medications into the log — that would put the most
sensitive data in the product into a second table with a different policy and a
longer retention, which is the opposite of what PRD §8 asks for. A lookup that
finds nothing is logged too: "did anyone go looking for this patient?" is the
question an audit answers.

`payment_webhook_events` is closed even to the super admin. It holds raw gateway
payloads including whatever the provider echoed back, and its only legitimate
reader is the webhook handler. Reconciliation reads `payments` — the same facts,
without the payload.

---

## 7. How this is proved

Four artefacts, each answering a question the others cannot.

| Artefact                                     | Question it answers                                                        |
| -------------------------------------------- | -------------------------------------------------------------------------- |
| `supabase/tests/03-rls/*.test.sql`           | Does each role see exactly what the table in §2 says?                      |
| `scripts/rls-attack-suite.sql`               | Is every attack denied, and denied in the right way?                       |
| `supabase/tests/03-rls/rls_enabled.test.sql` | Are the structural guarantees intact — RLS on, views safe, harness locked? |
| A live check through the API                 | Does any of it hold outside `psql`?                                        |

```bash
pnpm db:reset && pnpm db:test    # allow and deny, per role, per table
pnpm db:attacks                  # every statement must be denied
```

**Negative tests are first-class.** A suite that only asserts allows would pass
with security switched off entirely. Every allow has a deny beside it, and every
count is exact — "can read something" would still pass if a policy widened from
three rows to eleven.

**Denials are proved against tables that have rows in them.** "You cannot see it"
and "there is nothing there" are different claims, and only the first is a
security property. The suite checks that every table it declares invisible to
someone actually contains data.

### What makes it durable

The declared model is _data_, checked against the live database for completeness.
When a later module adds a table, the suite fails until someone writes down what
each role may do with it. Adding a table without declaring its rules is a build
failure, not a review comment — verified by the suite itself, which creates a
scratch table, watches the check fail, and drops it.

`db-tests` must therefore be a **required status check** on the default branch.
That is a repository setting rather than a file, and it is the last link in the
chain: without it the suite reports a failure a merge can ignore, and everything
above stops stopping anything.

### About the test harness

The suite impersonates users through a function that forges an identity, and it
ships to production because pgTAP has nowhere else to put it. Three things make
that acceptable, and the first is asserted by a test rather than trusted:

1. no signed-in user has access to the schema it lives in;
2. it is not reachable through the API at all;
3. the only roles that can call it already bypass every policy, so it grants them
   nothing they did not have.

---

## 8. Known limitations

Recorded rather than left to be discovered.

**Hospital-scoped audit reading is not implemented.** MODULE-PLAN §4.3 gave a
hospital admin access to their own hospital's audit rows. The audit table has no
hospital column — it records a table name, a row id and a snapshot — so scoping it
means either re-joining four tables on every read, or fishing the hospital out of
the snapshot, which works for appointments, tokens and sessions and silently fails
for payments, whose rows carry no hospital at all. **A tenancy filter that is
correct for three tables out of four is worse than none, because it reads as
complete.** So it is denied, and Module 5 should build hospital audit reporting as
a view that joins each row back to its hospital properly.

**Storage objects are not hospital-scoped.** Both image buckets are writable by
any hospital admin, not only for their own hospital's images. Storage paths carry
no tenancy, and a policy that resolved it from a client-supplied path would look
like a control without being one. The boundary that matters is on the hospital and
doctor records themselves: an admin can overwrite a file but cannot point another
hospital's card at it. Module 5 should close this properly with hospital-prefixed
paths.

**Refused reads are not audited.** A super admin denied a medical profile leaves
no record, because Postgres has no autonomous transactions — raising the error
rolls back the log row written alongside it. A run of refusals is exactly the
attack signal worth keeping, so this is a real gap; closing it needs an
out-of-transaction sink, which belongs with Module 15's observability work.

**Follow-ups are read-only.** Module 14 owns that workflow and opens the write
path with its own tests. Recorded here so it is a decision somebody changes
deliberately rather than a gap nobody noticed.

---

## 9. Open decisions

**Staff MFA.** PRD §8 says "recommended". The recommendation is to make it
**required** for hospital admins and the super admin before pilot, and optional
for doctors and reception during it. The check is already written into every
administrative policy and currently accepts every assurance level; turning it on
is a one-line change in `0020_security_helpers.sql`, and Module 5 owns the
enrolment UI that has to exist first.

**Support access to patient data — refused for V1.** PRD §10 leaves retention and
support access open. A support role that can read patient data for
troubleshooting has to be either designed properly or explicitly refused, and
refusing is the safer default: there is no such role, and a troubleshooting
request goes through the audited super-admin path where it leaves a record. Revisit
with the retention policy, which PRD §8 requires before launch either way.

**Anonymous discovery.** Currently refused (§2). Module 7's call.

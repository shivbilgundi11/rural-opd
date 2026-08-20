# Module 11 — Live Queue (Patient)

> **Phase 3 · Block E · Patient mobile · Depends on Module 10**

## 1. Summary

The screen the product exists for. PRD §1 G1 frames the whole goal as reducing
physical waiting uncertainty: a patient should be able to sit at home and know
where they stand.

That makes this module a trust exercise more than a technical one. A queue
position that is subtly stale, an ETA presented as a promise, or a screen that
looks live while showing three-minute-old data will send patients back to
waiting in the corridor — and the product will have failed even though every
API call succeeded.

So two rules shape every decision here: **always show how fresh the data is**,
and **never present an estimate as a commitment** (PRD §6.8).

## 2. Objectives

| ID  | Objective                                                         |
| --- | ----------------------------------------------------------------- |
| O1  | Token number, current token, people ahead, ETA (PAT-14)           |
| O2  | Refresh while the screen is active (PAT-15)                       |
| O3  | `TokenHeroCard` as the visually dominant element (`DESIGN.md` §5) |
| O4  | Freshness always visible; staleness never disguised               |
| O5  | ETA labelled as an estimate, everywhere it appears                |
| O6  | Token Detail → Live Queue → Arrival Guidance flow (TA §5)         |
| O7  | Read-only offline behaviour with honest labelling                 |
| O8  | Home's active-token slot populated (TA §5)                        |

## 3. Requirement traceability

| Source         | Requirement                                               | Deliverable               |
| -------------- | --------------------------------------------------------- | ------------------------- |
| PAT-14         | Show token number, current token, people ahead, ETA       | `TokenHeroCard`           |
| PAT-15         | Poll / refresh queue while screen is active               | Polling strategy          |
| PAT-13         | Token displayed only after server confirmation            | Reads token rows only     |
| PRD §3.2       | Live queue journey                                        | Queue screens             |
| PRD §6.8       | ETA advisory, clearly labelled                            | ETA presentation rules    |
| PRD §1.2       | No offline mutation of queue/token state                  | Offline read-only         |
| TA §5          | Queue: Token Detail → Live Queue → Arrival Guidance       | Navigation                |
| TA §6          | Realtime on published, RLS-protected views                | Optional realtime upgrade |
| `DESIGN.md` §5 | Dominant token number, count-up animation, "last updated" | `TokenHeroCard`           |
| `DESIGN.md` §4 | Status change: 300ms spring with slight overshoot         | Status transitions        |
| `DESIGN.md` §6 | No information by animation alone                         | Reduced-motion fallbacks  |

## 4. In scope

### 4.1 `TokenHeroCard` (`DESIGN.md` §5)

- Token number and current token are the largest, highest-contrast elements on
  screen — larger than the app bar, larger than any button.
- People ahead, estimated wait, session and doctor context.
- **"Last updated HH:MM"** always visible, never hidden behind a gesture.
- Count-up animation on refresh rather than a hard cut.
- `StatusBadge` from the token's backend status — icon plus text.

### 4.2 Queue data

- `get_queue_position(token_id)` RPC returning: token number, current token,
  people ahead, tokens completed, average consultation minutes, session status,
  and a server `snapshot_at` timestamp.
- People ahead counts only tokens in `WAITING` ahead of this one — skipped and
  completed tokens are excluded, because a patient counting heads in a corridor
  will notice if the app disagrees.
- ETA computed from `people_ahead × avg_consult_minutes`, adjusted by observed
  throughput once the session has enough completed consultations to be
  meaningful.

### 4.3 Refresh strategy

- react-query polling while the screen is focused and the app is foregrounded:
  every 15s in a normal queue, every 5s when the patient is within three
  positions, paused when backgrounded.
- Refetch immediately on screen focus and on app foreground.
- Optional Supabase Realtime subscription on a published queue view; polling
  remains the baseline and is never removed. Realtime is an enhancement, not a
  dependency — a dropped socket on a rural network must not stop updates.
- Pull-to-refresh always available.

### 4.4 Freshness and staleness

- Data older than 60s renders the timestamp in `warning` tone with an explicit
  "Updating…" or "Tap to refresh" affordance.
- On failure, the last known values remain visible with an unmistakable stale
  marker — blanking the screen is worse than showing old data honestly.
- Offline shows `OfflineBanner` plus the last snapshot with its age.

### 4.5 Arrival guidance (TA §5)

A screen answering "when should I leave?": estimated wait, hospital address,
travel-time prompt, and the guidance to arrive before being called. Explicitly
framed as advisory. No promise, no countdown to a specific minute.

### 4.6 Status transitions

When the token moves to `CALLED`, the card animates with the 300ms spring from
`DESIGN.md` §4, the badge changes, and prominent arrival instructions appear.
`RECALLED`, `SKIPPED`, `IN_CONSULTATION` and `COMPLETED` each have defined
presentations. With reduced motion, all changes are instant and the information
is still fully conveyed by text and icon.

### 4.7 Home integration

Home's `ActiveTokenSlot` (from Module 6) shows a compact token summary when an
active token exists, and deep-links into the queue screen.

## 5. Out of scope

| Item                                                | Deferred to |
| --------------------------------------------------- | ----------- |
| Staff queue transitions (call/recall/skip/complete) | Module 12   |
| Check-in by reception                               | Module 12   |
| Push notification on token called                   | Module 13   |
| Follow-ups after consultation                       | Module 14   |
| Queue analytics for hospitals                       | Module 12   |

Until Module 12 exists, queue progression is tested by advancing state with SQL.

## 6. Dependencies

**Upstream:** Module 10 (tokens exist and are unique), Module 6 (query client,
navigation, Home slots), Module 4 (`CountUp`, motion, `StatusBadge`), Module 3
(policies restricting a patient to their own token).

**Downstream:** Module 12's transitions are observed here; Module 13's
notifications deep-link here.

## 7. Deliverables

```
supabase/migrations/
  0070_get_queue_position_rpc.sql
  0071_queue_realtime_publication.sql
apps/mobile/src/features/queue/
  screens/{TokenDetail,LiveQueue,ArrivalGuidance}.tsx
  components/{TokenHeroCard,QueueProgress,FreshnessLabel,EtaEstimate}.tsx
  hooks/{useQueuePosition,useQueueRealtime,useActiveToken}.ts
apps/mobile/app/queue/[tokenId].tsx
docs/QUEUE.md   (refresh policy, ETA method, staleness rules)
```

## 8. Acceptance criteria

- [ ] A patient with a token sees token number, current token, people ahead and
      an ETA labelled as an estimate.
- [ ] Token number and current token are the largest elements on the screen.
- [ ] "Last updated" is always visible and accurate.
- [ ] Advancing the queue (staff action or SQL) updates the patient screen
      within one poll interval, with a count-up rather than a jump.
- [ ] Two devices holding tokens in the same session show consistent, converging
      positions as the queue advances.
- [ ] Data older than 60s is visibly marked stale.
- [ ] A failed refresh keeps the last values with a stale marker — never a blank
      screen or an infinite spinner.
- [ ] Airplane mode: last snapshot plus offline banner plus age; no mutation is
      attempted or queued.
- [ ] Backgrounding the app stops polling; foregrounding refetches immediately.
- [ ] Token `CALLED` animates per `DESIGN.md` §4 and shows arrival instructions.
- [ ] With reduced motion enabled, every state change is conveyed without
      animation.
- [ ] ETA never appears without the word "estimate" or equivalent (asserted by
      test).
- [ ] Home shows the active token and deep-links into the queue.
- [ ] A patient cannot read another patient's queue position via the RPC.

## 9. Test requirements

| Test                          | Type        | Asserts                                                          |
| ----------------------------- | ----------- | ---------------------------------------------------------------- |
| `queue_position.test.sql`     | pgTAP       | People-ahead excludes completed/skipped; correct across statuses |
| `queue_position.rls.test.sql` | pgTAP       | Another patient's token id returns denial, not data              |
| `eta.test.ts`                 | unit        | Estimation method; degrades sensibly with no throughput data     |
| `TokenHeroCard.test.tsx`      | component   | Hierarchy, freshness label, count-up, badge icon+text            |
| `staleness.test.tsx`          | component   | 60s threshold; failed refresh retains values                     |
| `polling.test.tsx`            | component   | Interval by proximity; pauses backgrounded; refetches on focus   |
| `eta-labelling.test.tsx`      | component   | No ETA rendering without an estimate qualifier                   |
| `two-device.e2e`              | integration | Convergent positions as the queue advances                       |

## 10. Risks & mitigations

| Risk                                     | Impact                                       | Mitigation                                                                             |
| ---------------------------------------- | -------------------------------------------- | -------------------------------------------------------------------------------------- |
| Stale data presented as live             | Patient misses their turn; trust destroyed   | Freshness timestamp always visible; 60s stale threshold; failed refresh clearly marked |
| ETA read as a promise                    | Complaints, and clinical pressure on doctors | PRD §6.8 labelling enforced by a test; arrival guidance framed as advisory             |
| Aggressive polling                       | Battery and data cost on a cheap phone       | Proximity-based intervals; paused when backgrounded; realtime as optional upgrade      |
| Realtime treated as the primary channel  | Silent staleness when the socket drops       | Polling always runs; realtime only triggers an early refetch                           |
| People-ahead disagrees with the corridor | Patients stop trusting the app               | Count only `WAITING` tokens ahead; verified against staff view in Module 12            |
| Count-up animation on a large jump       | Looks broken                                 | Cap the animation duration; jump instantly beyond a threshold                          |
| Patient refreshes obsessively            | Server load and data cost                    | Pull-to-refresh throttled; explain the auto-refresh cadence in copy                    |

## 11. Open decisions

- **ETA method.** Recommendation: start with `people_ahead ×
avg_consult_minutes` and switch to observed throughput once a session has
  ≥5 completed consultations, since a doctor's real pace diverges from the
  configured average. Both are advisory; neither changes the labelling rule.
- **Realtime vs polling for pilot.** Recommendation: ship polling only for the
  first pilot. It is simpler, predictable on poor networks, and TA §6 already
  marks realtime as optional. Add realtime once real usage data exists.

## 12. Definition of done

Two patients in different villages, both holding tokens for the same session,
watch their positions advance in step as the doctor works — each screen honestly
showing when it last heard from the server, and neither ever claiming to know
exactly when they will be seen.

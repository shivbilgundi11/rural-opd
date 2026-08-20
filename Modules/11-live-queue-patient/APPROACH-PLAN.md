# Module 11 — Approach Plan

## 0. Guiding principles

1. **Freshness is part of the data.** Every queue number travels with the
   timestamp it was true at, and the UI renders both. A number without an age is
   a claim the app cannot support.
2. **Estimates are labelled at the point of display**, not in a footnote. PRD
   §6.8 is a product requirement, not a legal disclaimer.
3. **Polling is the baseline; realtime is a bonus.** Anything that must work on
   a rural connection cannot depend on a persistent socket.
4. **Degrade to honest, never to blank.** Old data with a stale marker beats a
   spinner every time.

## 1. Build order

### Step 1 — `get_queue_position` RPC (`0070`)

```sql
create or replace function get_queue_position(p_token_id uuid)
returns table (
  token_id uuid, token_number integer, token_status token_status,
  current_token_number integer, people_ahead integer,
  completed_count integer, avg_consult_minutes integer,
  observed_minutes_per_patient numeric, session_status session_status,
  doctor_name text, hospital_name text, session_date date,
  start_time time, snapshot_at timestamptz)
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
declare v_tok opd_tokens%rowtype;
begin
  select * into v_tok from opd_tokens where id = p_token_id;
  if not found then raise exception 'TOKEN_NOT_FOUND'; end if;

  -- SECURITY DEFINER bypasses RLS, so authorise explicitly
  if v_tok.patient_id not in (select patient_ids_for_current_user())
     and not is_staff() then
    raise exception 'NOT_AUTHORIZED' using errcode = '42501';
  end if;

  return query
  select
    v_tok.id, v_tok.token_number, v_tok.status,
    s.current_token_number,
    (select count(*)::int from opd_tokens t
      where t.session_id = v_tok.session_id
        and t.status = 'WAITING'                 -- only genuinely waiting
        and t.token_number < v_tok.token_number),
    (select count(*)::int from opd_tokens t
      where t.session_id = v_tok.session_id and t.status = 'COMPLETED'),
    s.avg_consult_minutes,
    (select case when count(*) >= 5
              then extract(epoch from (max(completed_at) - min(consultation_started_at)))
                   / 60.0 / nullif(count(*), 0)
            end
       from opd_tokens t
      where t.session_id = v_tok.session_id and t.status = 'COMPLETED'),
    s.status, d.full_name, h.name, s.session_date, s.start_time,
    now()
  from opd_sessions s
  join doctors d   on d.id = s.doctor_id
  join hospitals h on h.id = s.hospital_id
  where s.id = v_tok.session_id;
end $$;
```

Three deliberate choices.

**`status = 'WAITING'` for people-ahead.** A patient in a corridor counts heads.
If the app includes skipped or already-completed tokens in "people ahead", the
app and reality diverge visibly, and the patient believes reality. Excluding
them is the difference between an app people trust and one they check against
the corridor.

**`observed_minutes_per_patient` is null below five completions.** A doctor's
real pace after two patients is noise. Returning null lets the client fall back
to the configured average rather than showing a wild estimate.

**`snapshot_at` comes from the server.** Cheap Android devices frequently have
wrong clocks; computing freshness from device time would mislabel fresh data as
stale, or worse, the reverse.

The explicit authorisation check is required because `SECURITY DEFINER` bypasses
Module 3's policies — the same obligation every definer function in this project
carries.

### Step 2 — Client hook with proximity-based polling

```ts
export function useQueuePosition(tokenId: string) {
  const isFocused = useIsFocused();
  const appActive = useAppActive();

  const query = useQuery({
    queryKey: queueKeys.position(tokenId),
    queryFn: async () => {
      const { data } = await supabase
        .rpc("get_queue_position", { p_token_id: tokenId })
        .single()
        .throwOnError();
      return { ...data, receivedAt: Date.now(), serverAt: data.snapshot_at };
    },
    refetchInterval: (q) => {
      if (!isFocused || !appActive) return false; // PAT-15: active screen only
      const d = q.state.data;
      if (!d) return 15_000;
      if (isTerminal(d.token_status)) return false; // completed/cancelled: stop
      if (d.people_ahead <= 3) return 5_000; // close to being called
      return 15_000;
    },
    staleTime: 0, // overrides Module 6's global 30s — queue is never "fresh enough"
    placeholderData: keepPreviousData, // keep showing the last numbers while refetching
  });

  useAppStateEffect((s) => {
    if (s === "active") query.refetch();
  });
  useFocusEffect(
    useCallback(() => {
      query.refetch();
    }, [tokenId]),
  );

  return query;
}
```

`staleTime: 0` is the deliberate override Module 6 anticipated. `keepPreviousData`
is what prevents the numbers blanking during every refetch — on a slow
connection that flicker reads as instability in the queue itself.

Polling stops on terminal statuses. A completed token that keeps polling every
15 seconds until the app closes is a battery cost with no information value.

### Step 3 — Freshness, computed against server time

```ts
export function useFreshness(serverAt: string, receivedAt: number) {
  const [now, setNow] = useState(Date.now());
  useInterval(() => setNow(Date.now()), 1_000);
  // age = time since we received it, anchored to the server's stamp
  const ageMs = now - receivedAt;
  return {
    ageMs,
    label: formatAge(ageMs), // "just now" / "2 min ago"
    isStale: ageMs > 60_000,
    displayTime: formatTimeFromServer(serverAt),
  };
}
```

Age is measured from local receipt (a duration, which a wrong clock does not
distort) while the displayed timestamp comes from the server. Using
`Date.now() - new Date(serverAt)` directly would show "12 minutes ago" on a
device whose clock is twelve minutes fast.

### Step 4 — `TokenHeroCard`

```tsx
export function TokenHeroCard({ data }: { data: QueuePosition }) {
  const fresh = useFreshness(data.snapshot_at, data.receivedAt);
  const reduced = useReducedMotion();
  return (
    <Card tone={data.token_status === "CALLED" ? "success" : "default"}>
      <View className="items-center gap-2">
        <Text className="text-sm text-text-muted">Your token</Text>
        {/* dominant element on the screen — DESIGN.md §5 */}
        <CountUp
          value={data.token_number}
          className="text-[64px] leading-none
                  text-primary-green font-semibold"
          instant
        />
        <StatusBadge status={data.token_status} />

        <View className="h-px w-full bg-border-subtle my-3" />

        <View className="flex-row justify-between w-full">
          <Stat
            label="Now serving"
            value={
              <CountUp
                value={data.current_token_number}
                className="text-[40px]"
                instant={reduced}
              />
            }
          />
          <Stat label="Ahead of you" value={`${data.people_ahead}`} />
        </View>

        <EtaEstimate
          people={data.people_ahead}
          perPatient={data.observed_minutes_per_patient ?? data.avg_consult_minutes}
          isObserved={data.observed_minutes_per_patient != null}
        />

        <FreshnessLabel {...fresh} onRefresh={refetch} />
      </View>
    </Card>
  );
}
```

The token number uses `instant` count-up (it never changes) while "Now serving"
animates — that is the number the patient watches, and `DESIGN.md` §5 asks for a
count-up rather than a hard cut.

Type scale note: 64px and 40px sit outside `DESIGN.md` §2's 12–30 scale. That is
intentional and needs recording in `docs/QUEUE.md` — §5 requires these to be
"the largest, highest-contrast elements", which cannot be satisfied within the
body scale. They are added to the token file as `display.hero` and `display.sub`
rather than written as arbitrary values, so the scale stays closed.

### Step 5 — ETA, labelled at the point of display

```tsx
export function EtaEstimate({ people, perPatient, isObserved }: Props) {
  if (people === 0) return <Text className="text-base">You’re next</Text>;
  const mins = Math.round(people * perPatient);
  const range = `${Math.max(5, mins - 10)}–${mins + 10} min`;
  return (
    <View className="flex-row items-center gap-2">
      <Clock size={16} color={tokens.text.muted} />
      <Text className="text-base text-text-primary">Estimated wait {range}</Text>
      <Text className="text-xs text-text-muted">
        {isObserved ? "based on today’s pace" : "based on usual timings"}
      </Text>
    </View>
  );
}
```

A **range**, not a point value. `47 minutes` invites a patient to plan to the
minute; `40–60 min` communicates the same information with its uncertainty
attached. The word "Estimated" is inside the component so no call site can
render the number without it — a test asserts this.

### Step 6 — Status transitions

```tsx
const pulse = useSharedValue(1);
useEffect(() => {
  if (status === "CALLED" && !reduced) {
    pulse.value = withSequence(
      withSpring(1.06, motion.statusChange),
      withSpring(1, motion.statusChange),
    );
  }
}, [status]);
```

300ms spring with slight overshoot (`DESIGN.md` §4). When `CALLED`, the card
also swaps in prominent instructions ("Go to Room 3 now") — because the
animation is decoration and the text is the information (`DESIGN.md` §6).

`SKIPPED` is the state that needs the most care: it must explain what happened
and what to do ("You were called and not present. Please contact reception to be
called again"), with a contact action. A skipped patient with no next step is
exactly the dead-end `DESIGN.md` §5 forbids.

### Step 7 — Offline and error degradation

```tsx
if (query.isError && query.data) {
  return (
    <>
      <StaleBanner age={fresh.label} onRetry={query.refetch} />
      <TokenHeroCard data={query.data} dimmed />
    </>
  );
}
if (query.isError && !query.data) {
  return (
    <ErrorState
      title="Can’t reach the hospital’s system"
      primaryAction={{ label: "Try again", onPress: query.refetch }}
      secondaryAction={{ label: "Call reception", onPress: callReception }}
    />
  );
}
```

The first branch is the important one: a refresh failure never removes numbers
the patient already has. It dims them, marks the age, and offers a retry.

No mutation path exists on this screen at all — PRD §1.2 excludes offline
mutation of queue state, and the simplest way to honour that is for the screen to
have nothing to mutate.

### Step 8 — Optional realtime (behind a flag)

```ts
useEffect(() => {
  if (!FEATURES.queueRealtime) return;
  const ch = supabase
    .channel(`session:${sessionId}`)
    .on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "opd_tokens",
        filter: `session_id=eq.${sessionId}`,
      },
      () => queryClient.invalidateQueries({ queryKey: queueKeys.position(tokenId) }),
    )
    .subscribe();
  return () => {
    supabase.removeChannel(ch);
  };
}, [sessionId]);
```

Realtime only **triggers a refetch** — it never supplies data directly. That
keeps one code path for reading queue state, keeps the RLS check in the RPC, and
means a dropped socket degrades to normal polling rather than to silence.
Recommendation stands to keep the flag off for the first pilot.

### Step 9 — Home's active-token slot

`useActiveToken()` finds any token in a non-terminal state and renders a compact
card in the slot Module 6 reserved, positioned directly below the Book OPD
action per TA §5's ordering.

## 2. Key technical decisions

| Decision        | Chosen                                    | Rejected                  | Rationale                                        |
| --------------- | ----------------------------------------- | ------------------------- | ------------------------------------------------ |
| People ahead    | `WAITING` only                            | all tokens below yours    | Must match what a patient counts in the corridor |
| ETA display     | range + qualifier                         | point estimate            | Communicates uncertainty; PRD §6.8               |
| ETA source      | observed pace after 5 completions         | always configured average | A doctor's real pace diverges quickly            |
| Freshness       | duration since receipt + server timestamp | client clock arithmetic   | Cheap Android clocks are unreliable              |
| Poll interval   | 5s within 3 positions, else 15s           | fixed 10s                 | Battery and data on the target device            |
| Terminal tokens | stop polling                              | keep polling              | No information value                             |
| Realtime        | optional refetch trigger                  | primary data channel      | Sockets drop on rural networks                   |
| Failed refresh  | keep values, mark stale                   | clear and show error      | Old-but-labelled beats blank                     |
| Hero type sizes | new `display` tokens                      | arbitrary inline values   | Keeps `DESIGN.md` §2's scale closed              |

## 3. Testing approach

Position correctness in pgTAP, because that is where the definition lives:

```sql
-- tokens 1..10; 1-3 completed, 4 skipped, 5 in consultation, 6 is ours
select is((select people_ahead from get_queue_position('<token6>')), 0,
          'completed, skipped and in-consultation tokens are not "ahead"');
```

That single assertion encodes the whole trust argument for this screen.

Component tests:

- `TokenHeroCard` — token number is the largest rendered font size on screen;
  badge has both an icon and text; freshness label present.
- Staleness — advance fake timers past 60s, assert the stale treatment.
- ETA labelling — render across many inputs and assert the string always
  contains "Estimated" or "You're next". This is the test that keeps PRD §6.8
  true as the screen evolves.
- Reduced motion — assert the final numbers are present immediately and the
  status is conveyed in text.

Two-device integration: issue two tokens in one session, advance
`current_token_number` and token statuses via SQL, assert both devices converge
within one poll interval and neither shows a position the other contradicts.

## 4. Verification script

```bash
supabase test db
pnpm --filter mobile start          # two physical devices, same session
```

1. Both devices show their token numbers, "Now serving", people ahead and an
   estimate range with a freshness label.
2. `update opd_sessions set current_token_number = 5 …` → both update within 15s
   with a count-up.
3. Complete tokens via SQL → "ahead of you" decreases correctly on both.
4. Set one token to `CALLED` → that device animates, shows arrival instructions,
   badge changes; the other is unaffected.
5. Set a token to `SKIPPED` → clear explanation plus a contact action.
6. Airplane mode on one device → offline banner, last numbers retained with age.
7. Background it for two minutes → foreground → immediate refetch, fresh label.
8. Reduced motion on → repeat steps 2 and 4 → all information still conveyed.
9. Call `get_queue_position` with the other patient's token id → denied.
10. Set the device clock 15 minutes fast → freshness still reads "just now".

Steps 6, 7 and 10 are the ones that separate a demo from something usable in a
village with intermittent signal.

## 5. Gotchas

- **`refetchInterval` as a function re-evaluates after each fetch**, so
  proximity-based intervals only change after the next poll — acceptable here,
  but do not expect an instant switch to 5s.
- **`useIsFocused` alone is not enough**; a focused screen in a backgrounded app
  still polls. Combine with `AppState`.
- **`.single()` on an RPC returning a table** throws when zero rows come back —
  handle `TOKEN_NOT_FOUND` explicitly rather than surfacing a PostgREST error.
- **`CountUp` on a large delta** (token 4 → 47 after a long background) looks
  broken; cap the animation and jump beyond a threshold.
- **Realtime requires the table in the publication and RLS on the channel** —
  and a patient must not receive other patients' row changes. If that cannot be
  proven, keep the flag off.
- **Don't put a "refresh" button next to the auto-refresh label** without
  throttling it; anxious patients will tap it continuously.
- **Never show "You'll be called at 11:42."** The moment a specific time appears,
  every downstream conversation becomes about that promise.

## 6. Handoff to Module 12

Module 12 receives: a patient-facing queue whose numbers come from
`get_queue_position`, the rule that people-ahead counts only `WAITING` tokens
(the staff console must agree exactly), and a two-device verification harness it
can reuse to prove staff actions land on patient screens.

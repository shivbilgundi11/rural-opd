# Module 7 — Approach Plan

## 0. Guiding principles

1. **Filter on the server.** Every filter, search term and page bound goes into
   the PostgREST query. Downloading 400 doctors to filter three is a data-cost
   problem for the user, not just a performance one.
2. **Availability is computed in one place.** A database view owns the
   definition of "bookable". The client never re-derives it, or Module 8 will
   disagree with Module 7 and patients will hit errors after committing.
3. **Disabled beats hidden.** A full or closed session shown greyed out with a
   reason is trustworthy. A missing session looks like a broken app.
4. **Reserve space before content arrives.** Fixed-height image slots and
   skeletons that match final layout — `DESIGN.md` §5's "no layout shift".

## 1. Build order

### Step 1 — The availability view (`0030_availability_view.sql`)

This is the module's keystone and is built first.

```sql
create view v_bookable_sessions with (security_invoker = true) as
select
  s.id as session_id, s.hospital_id, s.doctor_id,
  s.session_date, s.start_time, s.end_time,
  s.capacity, s.status, s.avg_consult_minutes,
  d.full_name as doctor_name, d.specialty, d.consultation_fee_paise,
  h.name as hospital_name, h.city, h.latitude, h.longitude,
  s.capacity - coalesce(u.used, 0) as remaining_capacity,
  (s.status in ('SCHEDULED','ACTIVE')
   and d.is_active and h.is_active
   and (s.session_date > current_date
        or (s.session_date = current_date and s.end_time > current_time))
   and s.capacity - coalesce(u.used, 0) > 0) as is_bookable
from opd_sessions s
join doctors d   on d.id = s.doctor_id
join hospitals h on h.id = s.hospital_id
left join lateral (
  select count(*) as used
  from appointments a
  where a.session_id = s.id
    and a.status not in ('EXPIRED','CANCELLED','PAYMENT_FAILED','NO_SHOW')
) u on true;
```

The `not in (...)` list is the load-bearing detail. Counting only issued tokens
would let ten patients hold `PENDING_PAYMENT` appointments against a
five-capacity session and all get tokens when their payments confirm — a
capacity breach that only appears under load, at a real clinic, on pilot day.
Counting live pending appointments prevents it.

`security_invoker = true` keeps Module 3's policies in force through the view.

Add supporting indexes:

```sql
create index on appointments (session_id) where status not in
  ('EXPIRED','CANCELLED','PAYMENT_FAILED','NO_SHOW');
create index on opd_sessions (hospital_id, session_date);
create index on doctors (hospital_id, specialty) where is_active;
```

### Step 2 — API layer

```ts
// api/hospitals.ts
export async function fetchHospitals(params: {
  search?: string;
  page: number;
  pageSize: number;
}) {
  let q = supabase
    .from("hospitals")
    .select("id,name,city,district,image_path,latitude,longitude", { count: "exact" })
    .eq("is_active", true)
    .order("name")
    .range(params.page * params.pageSize, (params.page + 1) * params.pageSize - 1);

  if (params.search)
    q = q.or(`name.ilike.%${params.search}%,city.ilike.%${params.search}%`);
  return q;
}
```

Note `.eq("is_active", true)` even though Module 3's policy already restricts to
active hospitals for patients. The policy is the security control; the explicit
filter is the correctness control. Relying on a policy for business filtering
means a policy change silently alters product behaviour.

Doctor queries read `v_bookable_sessions` so availability filtering happens
where the definition lives:

```ts
export async function fetchDoctors(f: DoctorFilters) {
  let q = supabase
    .from("v_bookable_sessions")
    .select(
      "doctor_id,doctor_name,specialty,consultation_fee_paise,hospital_id," +
        "hospital_name,session_id,session_date,start_time,remaining_capacity",
    )
    .eq("is_bookable", true)
    .gte("session_date", f.fromDate)
    .lte("session_date", f.toDate)
    .order("session_date")
    .order("start_time");
  if (f.hospitalId) q = q.eq("hospital_id", f.hospitalId);
  if (f.specialty) q = q.eq("specialty", f.specialty);
  return q;
}
```

Rows are grouped into doctors client-side (a doctor has several sessions), which
is cheap because the server already bounded the result set by date range.

### Step 3 — Query hooks and keys

A single key factory, so cache invalidation in Modules 8 and 11 is predictable:

```ts
export const discoveryKeys = {
  all: ["discovery"] as const,
  hospitals: (s?: string) => [...discoveryKeys.all, "hospitals", s ?? ""] as const,
  hospital: (id: string) => [...discoveryKeys.all, "hospital", id] as const,
  doctors: (f: DoctorFilters) => [...discoveryKeys.all, "doctors", f] as const,
  sessions: (docId: string, range: string) =>
    [...discoveryKeys.all, "sessions", docId, range] as const,
};
```

Session availability gets a shorter `staleTime` than catalogue data — capacity
changes minute to minute, a hospital's address does not:

```ts
useQuery({ queryKey: discoveryKeys.sessions(id, range),
           queryFn: ..., staleTime: 15_000 });   // vs the global 30s
```

### Step 4 — Search with debounce and cancellation

```tsx
const [raw, setRaw] = useState("");
const search = useDebouncedValue(raw, 300);
const { data, isFetching } = useQuery({
  queryKey: discoveryKeys.hospitals(search),
  queryFn: ({ signal }) =>
    fetchHospitals({ search, page: 0, pageSize: 20 }).abortSignal(signal),
  placeholderData: keepPreviousData, // list doesn't blank between keystrokes
});
```

`keepPreviousData` matters more on a slow connection than a fast one: without
it, every keystroke empties the list and re-runs the skeleton, which reads as
flickering rather than loading.

### Step 5 — Cards, built to the `DESIGN.md` §5 contract

```tsx
export function DoctorCard({ doctor, onPress }: Props) {
  return (
    <PressableScale
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={`${doctor.name}, ${doctor.specialty}, fee ${formatINR(doctor.feePaise)}`}
    >
      <Card>
        <View className="flex-row gap-3">
          {/* fixed slot — reserved before the image resolves */}
          <View className="h-16 w-16 rounded-card overflow-hidden bg-surface-alt">
            <Image
              source={doctor.imageUrl}
              style={{ flex: 1 }}
              contentFit="cover"
              transition={150}
              cachePolicy="memory-disk"
              placeholder={BLURHASH}
            />
          </View>
          <View className="flex-1">
            <Text className="text-base text-text-primary">{doctor.name}</Text>
            <Text className="text-sm text-text-muted">{doctor.specialty}</Text>
            <Text className="text-sm text-text-primary">
              {formatINR(doctor.feePaise)}
            </Text>
            {doctor.nextSession ? (
              <SessionChip session={doctor.nextSession} />
            ) : (
              <Text className="text-sm text-text-muted">No upcoming OPD</Text>
            )}
          </View>
        </View>
      </Card>
    </PressableScale>
  );
}
```

The fixed 64×64 container is the whole no-layout-shift mechanism. The
`accessibilityLabel` reads the fee aloud, which matters for `DESIGN.md` §6 and
for the low-literacy audience the product targets.

`SessionChip` when unavailable:

```tsx
<Chip disabled tone="muted" icon={Ban}>
  Fully booked
</Chip>
```

Icon plus text, never colour alone (`DESIGN.md` §1).

### Step 6 — Lists and performance

```tsx
<FlashList
  data={doctors}
  estimatedItemSize={96}
  keyExtractor={(d) => d.id}
  renderItem={({ item }) => <DoctorCard doctor={item} onPress={...} />}
  ListEmptyComponent={
    isLoading ? <SkeletonList count={6} />
              : <EmptyState title="No doctors match these filters"
                            primaryAction={{ label: "Clear filters", onPress: reset }} />}
  onEndReached={fetchNextPage}
  onEndReachedThreshold={0.5}
/>
```

Stagger entrance (`DESIGN.md` §4, 40–60ms per item) applies to the **first
page only**. Re-staggering on every pagination append makes long lists feel
broken — a detail worth deciding once, here.

### Step 7 — Prefetch on press

```tsx
const onHospitalPress = (id: string) => {
  queryClient.prefetchQuery({
    queryKey: discoveryKeys.doctors({ hospitalId: id, ...defaultRange }),
    queryFn: () => fetchDoctors({ hospitalId: id, ...defaultRange }),
  });
  router.push(`/care/hospital/${id}`);
};
```

On a 3G connection this converts a visible skeleton into an instant screen often
enough to change how the app feels.

### Step 8 — Recently used providers

Stored locally (last five), written on doctor-detail view, read by Home's
`RecentProvidersSlot` from Module 6:

```ts
type RecentProvider = { hospitalId: string; doctorId: string; viewedAt: string };
```

Local rather than server-side: it is a convenience, it must work offline, and it
avoids writing patient behaviour data to the server for no clinical reason
(PRD §8 privacy).

### Step 9 — Images and signed URLs

Storage buckets are RLS-protected (Module 3), so URLs are signed and expire.
Cache signed URLs in react-query with a TTL shorter than the signature, keyed by
object path, and batch-sign per list page rather than per card — one request for
twenty images instead of twenty.

## 2. Key technical decisions

| Decision                | Chosen                             | Rejected                       | Rationale                                                     |
| ----------------------- | ---------------------------------- | ------------------------------ | ------------------------------------------------------------- |
| Availability definition | one DB view                        | client-side derivation         | Modules 7 and 8 must agree or patients hit post-commit errors |
| Capacity counting       | includes live pending appointments | issued tokens only             | Prevents overbooking via unpaid holds                         |
| Unavailable sessions    | disabled + reason                  | hidden                         | Hidden data reads as a broken app                             |
| Search                  | server-side `ilike` + debounce     | client-side over full download | Data cost on rural connections                                |
| Stagger animation       | first page only                    | every page                     | Repeated stagger feels like a glitch                          |
| Recently used           | local storage                      | server table                   | Offline-capable; no behavioural data on the server            |
| Distance                | sort option only                   | filter                         | A denied location permission must never hide results          |
| List                    | FlashList                          | ScrollView/map                 | 60fps on mid-range Android                                    |

## 3. Testing approach

pgTAP on the view is where correctness is proven, because that is where the rule
lives:

```sql
-- a session with capacity 2 and two PENDING_PAYMENT appointments is not bookable
select is((select is_bookable from v_bookable_sessions where session_id = '<s>'),
          false, 'pending payments consume capacity');
-- it becomes bookable again once one expires
update appointments set status='EXPIRED' where id='<a1>';
select is((select is_bookable from v_bookable_sessions where session_id = '<s>'),
          true, 'expired appointment frees capacity');
```

That second assertion is a direct test of PRD §6.4 ("pending appointments expire
and free up queue capacity") and is worth writing here even though Module 8 owns
the expiry job.

Component tests assert fee formatting, disabled chips carrying both icon and
text, accessibility labels, and touch-target sizes. Network tests assert
debounce timing and that an in-flight request is aborted on a new keystroke.

## 4. Verification script

```bash
# with the device on a throttled connection profile
pnpm --filter mobile start
```

1. Home → Book OPD → hospital list renders with skeletons then content, no jump.
2. Search "kolh" → debounced result, list never blanks.
3. Open a hospital → doctor list warm from prefetch.
4. Filter by specialty and "next 7 days" → correct sessions.
5. Open a doctor → fee reads ₹30.00; sessions listed with capacity.
6. In the staff web app (Module 5), set that session's capacity to its used
   count → pull to refresh → chip now reads "Fully booked", disabled.
7. Deactivate the doctor in the staff app → refresh → doctor disappears.
8. Airplane mode → cached lists still render with the offline banner → retry
   restores.
9. Deny location permission → lists work; no repeated prompts.

Steps 6 and 7 are the ones that prove Module 5 and Module 7 are actually talking
to each other rather than to seed data.

## 5. Gotchas

- **`.or()` with user input needs escaping.** A search term containing `,` or
  `)` breaks the PostgREST filter syntax; sanitise before interpolation.
- **`count: "exact"` is expensive** on large tables — use `planned` for lists
  where an approximate total is fine.
- **`expo-image` `transition` on a `contentFit="cover"` image can flash** if the
  placeholder aspect differs; use a solid token-coloured placeholder.
- **FlashList needs a stable `estimatedItemSize`**; a wrong one produces blank
  regions while scrolling fast — very visible on cheap devices.
- **Signed URL expiry shorter than react-query's `gcTime`** yields broken images
  after a few minutes in the background; keep the URL TTL longer than the cache
  TTL, not the reverse.
- **Don't add client-side `is_active` filtering as the only filter** — but don't
  remove it either; policy and product filter for different reasons.

## 6. Handoff to Module 8

Module 8 receives: `v_bookable_sessions` as the single definition of bookable, a
doctor-detail CTA carrying `{ doctorId, sessionId, feePaise }`, and query keys it
must invalidate after booking so capacity updates immediately across discovery
screens.

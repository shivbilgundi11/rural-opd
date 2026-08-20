# Module 14 — Approach Plan

## 0. Guiding principles

1. **The link table is the access control.** Every family feature works by
   creating or removing a row in `patient_family_links`. No screen filters data
   the policy would otherwise return; no query works around a denial.
2. **Unlink, never delete.** Clinical and financial history outlives a
   relationship in the app.
3. **Tell patients who can see what.** A medical profile screen that does not
   say a doctor will read it during consultation is collecting data under
   unclear terms.
4. **Extract strings before translating.** The i18n scaffold and layout
   verification can complete now, even though the language decision has not
   landed.

## 1. Build order

### Step 1 — Family member creation

The RPC creates the patient and the link atomically, so a failure cannot leave
an orphaned patient row nobody can reach:

```sql
create or replace function add_family_member(
  p_full_name text, p_relationship text,
  p_date_of_birth date, p_gender text, p_phone text default null)
returns patients language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_patient patients%rowtype;
begin
  if auth.uid() is null then raise exception 'NOT_AUTHENTICATED'; end if;

  insert into patients (full_name, date_of_birth, gender, phone,
                        created_by_auth_user_id, auth_user_id)
  values (p_full_name, p_date_of_birth, p_gender, p_phone,
          auth.uid(), null)                    -- dependents never have a login
  returning * into v_patient;

  insert into patient_family_links (owner_auth_user_id, patient_id, relationship)
  values (auth.uid(), v_patient.id, p_relationship);

  return v_patient;
end $$;
```

`auth_user_id = null` is what makes Module 3's insert policy accept the link. A
dependent is by construction an account-less patient created by this user — which
means the forgery path ("link me to patient X") has no legitimate counterpart to
hide behind.

**Why linking to an existing account-holding patient is not supported.** It
sounds reasonable — a husband and wife both have accounts, one should be able to
book for the other. But it requires a consent mechanism: an invitation, an
acceptance, revocation, and an audit trail of who approved what. Without that,
"link by phone number" is an unauthenticated read of someone's medical history.
V1 does not have the consent machinery, so V1 does not have the feature. This is
recorded in `docs/FAMILY-ACCESS.md` as a deliberate omission rather than an
oversight, along with what would be needed to add it properly.

### Step 2 — Unlink, preserving history

```sql
create or replace function remove_family_link(p_patient_id uuid)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  delete from patient_family_links
   where owner_auth_user_id = auth.uid() and patient_id = p_patient_id;
  if not found then raise exception 'LINK_NOT_FOUND' using errcode='42501'; end if;
  -- the patients row and all clinical/financial history are untouched
end $$;
```

The UI copy states this plainly: _"Removing a family member stops you from seeing
their appointments. Their visit and payment records are kept by the hospital."_

There is a real consequence worth surfacing in the UI: unlinking a dependent with
an active token means nobody can track that queue. The confirmation dialog checks
for active appointments and warns.

### Step 3 — Patient picker in the booking flow

Module 8 built the `BottomSheetPicker` with only "self". Now it has data:

```tsx
const { data: patients } = useQuery({
  queryKey: familyKeys.members(),
  queryFn: async () => {
    const { data } = await supabase
      .from("patients")
      .select("id,full_name,date_of_birth,gender,auth_user_id")
      .order("auth_user_id", { nullsFirst: false }); // self first, then dependents
    return data;
  },
});
```

No `.in("id", …)` filter and no client-side ownership check. Module 3's policy
already restricts this select to the user's own row plus linked patients — and
adding a redundant client filter would mean a future policy fix silently fails to
take effect here. The absence of a filter is the correct implementation.

Booking for a dependent then flows unchanged through Modules 8–11: the RPC's
ownership check (`p_patient_id not in (select patient_ids_for_current_user())`)
already accepts linked patients, which is why no payment or token code changes in
this module.

Notifications also work unchanged, because `notification_outbox.patient_id`
resolves to contact details through the **owner's** account when the patient has
no phone of their own. Verify this explicitly — it is the one place where a
dependent with no phone number could silently drop out of Module 13's delivery
path.

### Step 4 — Medical profile

```tsx
<ScreenContainer>
  <InfoBanner icon={Eye} tone="info">
    Your doctor can see this only while you are in consultation with them. Reception and
    other staff cannot see it.
  </InfoBanner>
  <TagInput label="Allergies" value={allergies} suggestions={COMMON_ALLERGIES} />
  <TagInput
    label="Current medicines"
    value={medications}
    suggestions={COMMON_MEDICINES}
  />
  <TagInput
    label="Ongoing conditions"
    value={conditions}
    suggestions={COMMON_CONDITIONS}
  />
  <Select label="Blood group" options={BLOOD_GROUPS} />
  <EmergencyContactFields />
</ScreenContainer>
```

The banner is a design requirement, not decoration. Module 3 built a
time-bounded access policy specifically so this statement would be true; saying
it out loud is what turns a technical control into informed consent.

Suggestions are plain string arrays — common allergens, common medicines in
local use — to reduce typing on a cheap keyboard in a second language. They are
explicitly **not** a coded vocabulary. PRD §1.2 excludes an EMR, and the moment
this becomes SNOMED-shaped, scope and regulatory exposure both change.

### Step 5 — Follow-ups

Rows already exist (Module 12 creates them on consultation completion) and the
`FOLLOW_UP_DUE` notification already deep-links here (Module 13). This module
builds the screens.

```tsx
export function FollowUpDetail({ id }: { id: string }) {
  const { data } = useFollowUp(id);
  return (
    <ScreenContainer>
      <Card>
        <Text className="text-lg">Follow-up with {data.doctorName}</Text>
        <Text className="text-sm text-text-muted">{data.hospitalName}</Text>
        <StatusBadge status={data.status} />
        <Text>Suggested date: {formatDate(data.dueDate)}</Text>
        {data.notes ? <Text>{data.notes}</Text> : null}
      </Card>
      <Button
        onPress={() =>
          router.push({
            pathname: "/care/doctor/[id]",
            params: { id: data.doctorId, patientId: data.patientId, followUpId: id },
          })
        }
      >
        Book this follow-up
      </Button>
      <Button variant="ghost" onPress={dismiss}>
        Not needed anymore
      </Button>
    </ScreenContainer>
  );
}
```

"Book this follow-up" carries `patientId` and `followUpId` into the Module 7/8
flow so the booking is pre-scoped to the right person and links back to its
source. Dismissal is patient-controlled and does not delete the record — the
doctor's recommendation stays in history.

Follow-ups cancel with their source appointment: if an appointment is cancelled
after a follow-up was created, the follow-up moves to `CANCELLED` too, so a
reminder never arrives for care that did not happen.

### Step 6 — History

```ts
const { data } = useInfiniteQuery({
  queryKey: historyKeys.list(patientFilter),
  queryFn: ({ pageParam }) =>
    supabase
      .from("v_patient_appointments")
      .select("*")
      .in("status", TERMINAL_STATUSES)
      .order("created_at", { ascending: false })
      .lt("created_at", pageParam ?? "infinity") // keyset, not offset
      .limit(20),
  getNextPageParam: (last) => last.at(-1)?.created_at,
});
```

Keyset pagination rather than `range()`: offsets get slower as history grows and
can skip or repeat rows when new appointments are inserted mid-scroll.

Visit detail shows token number, payment status (status only — never the payment
id or gateway reference), consultation outcome and any follow-up.

### Step 7 — i18n scaffold

```ts
// i18n/index.ts
import { I18n } from "i18n-js";
import en from "./en.json";
export const i18n = new I18n({ en });
i18n.enableFallback = true;
i18n.defaultLocale = "en";
```

Extract every user-facing string into `en.json`, enforced by lint:

```js
{ selector: "JSXText[value=/[A-Za-z]{4,}/]",
  message: "User-facing text must go through i18n (t('key'))." }
```

The layout work is what can be done _now_, before any translation exists:

- Snapshot tests with a pseudo-locale that inflates every string by 40% and
  swaps in Devanagari characters, asserting no clipping or overlap.
- Line-height ratios from Module 4 verified against Indic scripts, which need
  more vertical space than Latin at the same point size.
- Buttons and chips sized to grow rather than truncate.

This ordering matters: layout breakage discovered _after_ translations arrive
gets misdiagnosed as a translation problem and fixed by shortening text, which
degrades the copy for a layout bug.

The chosen language then feeds Module 13's template locale key, so a patient's
notifications match their app.

### Step 8 — Preferences and account deletion

Notification channel toggles write to the preferences record Module 13 reads.
Language selection writes `patients.locale`.

Account deletion files a support request rather than deleting, with copy that
says so honestly. PRD §10's retention decision has legal weight, and a delete
button that only pretends to delete would be worse than one that explains itself.

## 2. Key technical decisions

| Decision           | Chosen                                     | Rejected                     | Rationale                                                                   |
| ------------------ | ------------------------------------------ | ---------------------------- | --------------------------------------------------------------------------- |
| Dependents         | account-less patients created by the owner | link to any patient by phone | Linking without consent machinery is an unauthenticated medical-record read |
| Removal            | unlink only                                | cascade delete               | History must outlive a relationship                                         |
| Patient list query | no client-side filter                      | `.in(ownedIds)`              | The policy is the control; a client filter masks policy regressions         |
| Medical vocabulary | free text + suggestions                    | coded terminology            | PRD §1.2 excludes an EMR                                                    |
| Consent            | on-screen statement of visibility          | privacy policy link          | The person deciding what to type deserves to know who reads it              |
| History pagination | keyset                                     | offset                       | Stable and fast as history grows                                            |
| Duplicate patients | accepted, not merged                       | auto-merge on phone match    | Merging medical identities needs a policy first                             |
| i18n               | scaffold + layout now, content later       | wait for the decision        | Layout bugs found after translation get misdiagnosed                        |

## 3. Testing approach

The forgery tests come first, run directly against the API with a real JWT —
not through the UI:

```ts
// patient B tries to link to patient A's record
const { error } = await clientAsB.from("patient_family_links").insert({
  owner_auth_user_id: B_UID,
  patient_id: A_PATIENT_ID,
  relationship: "spouse",
});
expect(error?.code).toBe("42501");

// and to an account-holding patient created by themselves (blocked too)
const { error: e2 } = await clientAsB.from("patient_family_links").insert({
  owner_auth_user_id: B_UID,
  patient_id: C_ACCOUNT_PATIENT_ID,
  relationship: "friend",
});
expect(e2?.code).toBe("42501");
```

Revocation, across every table that carries family-scoped data:

```sql
select tests.set_auth_user('<owner>');
select isnt_empty($$ select 1 from appointments where patient_id='<dep>' $$);
select isnt_empty($$ select 1 from medical_profiles where patient_id='<dep>' $$);
select isnt_empty($$ select 1 from opd_tokens where patient_id='<dep>' $$);
select remove_family_link('<dep>');
select is_empty($$ select 1 from appointments where patient_id='<dep>' $$);
select is_empty($$ select 1 from medical_profiles where patient_id='<dep>' $$);
select is_empty($$ select 1 from opd_tokens where patient_id='<dep>' $$);
-- and the data still exists for the hospital
select tests.set_auth_user('<admin_h1>');
select isnt_empty($$ select 1 from appointments where patient_id='<dep>' $$);
```

That last pair of assertions — invisible to the ex-owner, still present for the
hospital — is exactly the behaviour PRD §6.7 implies and the one most likely to
be implemented wrongly as a delete.

Full family booking as an integration test: add dependent → book → pay (test
mode) → webhook → token → queue → notification to the owner's device.

## 4. Verification script

```bash
supabase test db
pnpm --filter mobile start
```

1. Profile → Family → add "Mother", relationship, DOB.
2. Book OPD → picker shows Self and Mother → choose Mother → pay in test mode.
3. Token issued for Mother; queue screen shows her token; Home's active-token
   slot shows it.
4. Doctor calls the token (Module 12) → the notification arrives on the owner's
   phone → tapping it opens Mother's queue screen.
5. Complete the consultation with a follow-up → follow-up appears in the list →
   the `FOLLOW_UP_DUE` deep link opens its detail → "Book this follow-up"
   prefills Mother and the same doctor.
6. Medical profile for Mother: add an allergy → confirm the doctor sees it only
   while she is `IN_CONSULTATION` (check before, during and after in the staff
   app).
7. Remove the family link → Mother's appointments, tokens and profile disappear
   from the app → confirm in the staff app that the hospital still sees them.
8. Via curl with the patient's JWT, attempt to link to a stranger's patient id → 403.
9. History: scroll 100+ appointments, filter by patient, open a visit detail.
10. Switch language → UI strings change → trigger a notification → template
    arrives in the same locale.
11. Pseudo-locale build → no clipped text on any screen at 200% font scale.

Steps 7 and 8 are the ones to demonstrate to anyone reviewing privacy.

## 5. Gotchas

- **A dependent with no phone number** cannot receive SMS. Module 13 must fall
  back to the owner's contact details; verify explicitly or dependents silently
  stop being notified.
- **`patient_ids_for_current_user()` is `stable`,** so it caches within a
  statement. After an unlink, invalidate the client cache — the policy is
  correct immediately, but a cached react-query result is not.
- **Ordering `nullsFirst: false` on `auth_user_id`** is what puts "self" at the
  top of the picker; without it the list order is arbitrary and users mis-tap.
- **Date of birth is used for age display only.** Do not derive clinical
  decisions from it — that is EMR territory.
- **i18n extraction misses `Alert.alert` and toast strings** more often than JSX;
  grep for them specifically.
- **Indic scripts need more line height** than the Latin ratios; verify with the
  pseudo-locale before translation, not after.
- **Don't auto-merge patients matched by phone.** A shared household phone
  number is common in exactly this user population, and merging two people's
  medical records is a serious error.

## 6. Handoff to Module 15

Module 15 receives a feature-complete V1: every PAT requirement implemented,
every screen using Module 4's primitives and passing its a11y harness, an i18n
catalogue awaiting pilot translations, and two open PRD §10 decisions (retention
and languages) that must land before pilot rather than before code.

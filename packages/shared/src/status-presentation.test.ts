/**
 * The rules `Record<Status, …>` cannot express on its own.
 *
 * Exhaustiveness is already handled by the compiler — a status added in a
 * migration breaks the build until it is given a label, a tone and an icon.
 * What the type cannot check is whether those choices are *right*, and two of
 * them carry a product rule rather than a preference.
 */

import { describe, expect, it } from "vitest";

import {
  APPOINTMENT_STATUSES,
  PAYMENT_STATUSES,
  TOKEN_STATUSES,
  type AppointmentStatus,
  type PaymentStatus,
  type TokenStatus,
} from "./enums";
import {
  APPOINTMENT_STATUS_PRESENTATION,
  PAYMENT_STATUS_PRESENTATION,
  TOKEN_STATUS_PRESENTATION,
  type StatusPresentation,
} from "./status-presentation";

const ALL: ReadonlyArray<
  [string, readonly string[], Record<string, StatusPresentation>]
> = [
  ["token", TOKEN_STATUSES, TOKEN_STATUS_PRESENTATION],
  ["appointment", APPOINTMENT_STATUSES, APPOINTMENT_STATUS_PRESENTATION],
  ["payment", PAYMENT_STATUSES, PAYMENT_STATUS_PRESENTATION],
];

describe.each(ALL)("%s statuses", (_name, statuses, presentation) => {
  it("covers every value the database can emit, and no others", () => {
    // The compile-time `Record` guarantees this for the *types*. This checks it
    // against the runtime member list, which is what a screen actually iterates
    // — the two come from the same generated file, so a disagreement means the
    // generator and the map have drifted.
    expect(Object.keys(presentation).sort()).toEqual([...statuses].sort());
  });

  it("gives every status a non-empty label and an icon", () => {
    // DESIGN.md §1: status is never communicated by colour alone. An empty
    // label would satisfy the type and defeat the rule.
    for (const status of statuses) {
      const entry = presentation[status];
      expect(entry?.label.trim(), status).not.toBe("");
      expect(entry?.icon, status).toBeTruthy();
    }
  });

  it("uses distinct labels, so two statuses never read the same", () => {
    // `IN_CONSULTATION` appears in both the token and appointment maps with the
    // same wording, which is intended — it is the same fact. Within one map,
    // two statuses sharing a label would make them indistinguishable to a
    // screen reader, which only ever gets the text.
    const labels = statuses.map((s) => presentation[s]?.label);
    expect(new Set(labels).size).toBe(labels.length);
  });
});

describe("DESIGN.md §1 — never show success before the server confirms it", () => {
  it("keeps every pending payment state amber", () => {
    // The rule this module is strictest about, and the one with a real cost if
    // it breaks: a green tick on a payment that has not settled tells a patient
    // they have paid when the gateway may still fail.
    const pending: PaymentStatus[] = ["CREATED", "PROCESSING"];
    for (const status of pending) {
      expect(PAYMENT_STATUS_PRESENTATION[status].tone, status).not.toBe("success");
    }
    expect(PAYMENT_STATUS_PRESENTATION.PROCESSING.tone).toBe("warning");
  });

  it("keeps unpaid appointment states off success too", () => {
    const notYetPaid: AppointmentStatus[] = [
      "DRAFT",
      "PENDING_PAYMENT",
      "PAYMENT_PROCESSING",
    ];
    for (const status of notYetPaid) {
      expect(APPOINTMENT_STATUS_PRESENTATION[status].tone, status).not.toBe("success");
    }
  });

  it("marks only genuinely settled states as success", () => {
    expect(PAYMENT_STATUS_PRESENTATION.SUCCESS.tone).toBe("success");
    expect(APPOINTMENT_STATUS_PRESENTATION.CONFIRMED.tone).toBe("success");
    expect(APPOINTMENT_STATUS_PRESENTATION.TOKEN_GENERATED.tone).toBe("success");
  });
});

describe("terminal failure states read as failures", () => {
  it("uses the danger tone for cancellation and no-show", () => {
    const failures: TokenStatus[] = ["CANCELLED", "NO_SHOW"];
    for (const status of failures) {
      expect(TOKEN_STATUS_PRESENTATION[status].tone, status).toBe("danger");
    }
  });

  it("does not use danger for a skipped token, which is recoverable", () => {
    // PRD §5.2 lets a skipped patient be recalled at any moment. Colouring it
    // the same as a no-show would tell someone still in the waiting room that
    // they had missed their turn for good.
    expect(TOKEN_STATUS_PRESENTATION.SKIPPED.tone).toBe("warning");
  });
});

import { describe, expect, it } from "vitest";

import {
  addPaise,
  amountsMatch,
  BASE_OPD_FEE_PAISE,
  formatINR,
  InvalidAmountError,
  isPaise,
  paise,
  paiseToRupees,
  rupeesToPaise,
  subtractPaise,
} from "./money";

describe("paise constructor", () => {
  it("accepts non-negative integers", () => {
    expect(paise(0)).toBe(0);
    expect(paise(3000)).toBe(3000);
  });

  it.each([1.5, -1, Number.NaN, Number.POSITIVE_INFINITY, Number.MAX_SAFE_INTEGER + 2])(
    "rejects %p",
    (value) => {
      expect(() => paise(value)).toThrow(InvalidAmountError);
    },
  );
});

describe("rupee conversion", () => {
  it("round-trips whole rupees", () => {
    for (const rupees of [0, 1, 30, 199, 12345]) {
      expect(paiseToRupees(rupeesToPaise(rupees))).toBe(rupees);
    }
  });

  it("converts the classic binary-float casualties exactly", () => {
    // 0.1 + 0.2 !== 0.3 in floats; in paise these are simply integers.
    expect(rupeesToPaise(0.1)).toBe(10);
    expect(rupeesToPaise(0.2)).toBe(20);
    expect(addPaise(rupeesToPaise(0.1), rupeesToPaise(0.2))).toBe(30);
    expect(rupeesToPaise(1.005)).toBe(101);
    expect(rupeesToPaise(29.99)).toBe(2999);
  });

  it("never drifts when summed a thousand times", () => {
    let total = paise(0);
    for (let i = 0; i < 1000; i += 1) total = addPaise(total, rupeesToPaise(0.01));
    expect(total).toBe(1000);
    expect(paiseToRupees(total)).toBe(10);
  });

  it("rounds at the paise boundary without inheriting float error", () => {
    expect(rupeesToPaise(30.004)).toBe(3000);
    // 30.005 * 100 is 3000.4999999999995 in binary float; a naive Math.round
    // would return 3000 and silently lose a paise.
    expect(rupeesToPaise(30.005)).toBe(3001);
    expect(rupeesToPaise(1.005)).toBe(101);
    expect(rupeesToPaise(8.165)).toBe(817);
  });
});

describe("formatINR", () => {
  it("formats the base OPD fee as ₹30.00", () => {
    // The en-IN locale may use a non-breaking space between symbol and digits.
    expect(formatINR(BASE_OPD_FEE_PAISE).replace(/\s/g, "")).toBe("₹30.00");
  });

  it("always shows two decimal places", () => {
    expect(formatINR(paise(5)).replace(/\s/g, "")).toBe("₹0.05");
    expect(formatINR(paise(100)).replace(/\s/g, "")).toBe("₹1.00");
  });

  it("groups in the Indian system", () => {
    expect(formatINR(paise(1_00_00_000)).replace(/\s/g, "")).toBe("₹1,00,000.00");
  });
});

describe("arithmetic", () => {
  it("adds and subtracts as integers", () => {
    expect(addPaise(paise(2500), paise(500))).toBe(3000);
    expect(subtractPaise(paise(3000), paise(500))).toBe(2500);
  });

  it("refuses to produce a negative amount", () => {
    expect(() => subtractPaise(paise(100), paise(500))).toThrow(InvalidAmountError);
  });
});

describe("amountsMatch — the PRD §6 invariant", () => {
  it("is exact equality, not tolerance", () => {
    expect(amountsMatch(BASE_OPD_FEE_PAISE, paise(3000))).toBe(true);
    expect(amountsMatch(BASE_OPD_FEE_PAISE, paise(2999))).toBe(false);
    expect(amountsMatch(BASE_OPD_FEE_PAISE, paise(3001))).toBe(false);
  });
});

describe("isPaise", () => {
  it.each([
    [0, true],
    [3000, true],
    [-1, false],
    [1.5, false],
    ["3000", false],
    [null, false],
  ])("isPaise(%p) === %p", (value, expected) => {
    expect(isPaise(value)).toBe(expected);
  });
});

describe("BASE_OPD_FEE_PAISE", () => {
  it("is INR 30 in paise — PRD §3.1", () => {
    expect(BASE_OPD_FEE_PAISE).toBe(3000);
    expect(paiseToRupees(BASE_OPD_FEE_PAISE)).toBe(30);
  });
});

import { describe, expect, it } from "vitest";

import { normalisePhone, paiseSchema, phoneSchema, e164PhoneSchema } from "./primitives";

describe("paiseSchema", () => {
  it("brands a valid integer", () => {
    expect(paiseSchema.parse(3000)).toBe(3000);
  });

  it.each([29.99, -1, "3000"])("rejects %p", (value) => {
    expect(() => paiseSchema.parse(value)).toThrow();
  });
});

describe("phoneSchema", () => {
  it.each(["9876543210", "+919876543210", " 9876543210 "])("accepts %p", (value) => {
    expect(() => phoneSchema.parse(value)).not.toThrow();
  });

  it.each(["1234567890", "98765", "+1 415 555 0100"])("rejects %p", (value) => {
    expect(() => phoneSchema.parse(value)).toThrow();
  });

  it("normalises every accepted form to one E.164 string", () => {
    expect(e164PhoneSchema.parse("9876543210")).toBe("+919876543210");
    expect(e164PhoneSchema.parse("+919876543210")).toBe("+919876543210");
    expect(normalisePhone("098765 43210")).toBe("+919876543210");
  });
});

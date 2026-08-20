/**
 * Zod schemas for values that cross a trust boundary: request bodies for Edge
 * Functions, gateway webhook payloads, and anything a client submits.
 *
 * Module 1 seeds only the primitives that later schemas compose from. Each
 * later module adds its own file here (`booking.ts` in Module 8,
 * `payment.ts` in Module 9, `webhook.ts` in Module 10).
 */

export * from "./primitives";

import { BASE_OPD_FEE_PAISE, formatINR } from "@rural-opd/shared";

import { env } from "./env";

import type { ReactElement } from "react";

/**
 * Module 1 wiring proof. This screen exists to demonstrate that the workspace
 * alias, the TypeScript path mapping and the Turborepo build graph all work on
 * the Vite side -- the same `formatINR(BASE_OPD_FEE_PAISE)` renders in the
 * mobile app. Module 5 replaces this with the real staff shell.
 */
export function App(): ReactElement {
  return (
    <main>
      <h1>Rural OPD -- Staff</h1>
      <p>
        Base OPD fee:{" "}
        <strong data-testid="base-fee">{formatINR(BASE_OPD_FEE_PAISE)}</strong>
      </p>
      <p>
        Environment: <code>{env.APP_ENV}</code>
      </p>
      <p>Module 1 wiring proof -- replaced by the staff shell in Module 5.</p>
    </main>
  );
}

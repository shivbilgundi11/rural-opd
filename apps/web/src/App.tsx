import { Link, Route, Routes } from "react-router-dom";

import { Gallery } from "@/routes/gallery";

import type { ReactElement } from "react";

/**
 * Module 1's wiring proof is gone; Module 5 builds the real staff shell here.
 *
 * What exists in the meantime is the design-system gallery, which is the only
 * route this app needs before there is an app. MODULE-PLAN §4.6 wants it
 * reachable in a browser so the two surfaces can be compared side by side.
 */
export function App(): ReactElement {
  return (
    <Routes>
      <Route path="/gallery" element={<Gallery />} />
      <Route
        path="*"
        element={
          <main className="flex flex-col gap-3 bg-surface-base p-6">
            <h1 className="text-2xl font-bold text-text-primary">Rural OPD — Staff</h1>
            <p className="text-base text-text-muted">
              The staff shell arrives in Module 5.
            </p>
            <Link className="text-base text-primary-blue underline" to="/gallery">
              Design system gallery
            </Link>
          </main>
        }
      />
    </Routes>
  );
}

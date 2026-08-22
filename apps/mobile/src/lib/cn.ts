import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * The same helper as `apps/web/src/lib/cn.ts`, duplicated rather than shared.
 *
 * Sharing it would mean a package that both surfaces import, and the only thing
 * in it would be two library calls. The cost of the duplication is bounded — it
 * has no design values in it — and the alternative adds a workspace package to
 * the build graph for four lines. The values that must not diverge live in
 * `@rural-opd/tokens`; this is plumbing.
 */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

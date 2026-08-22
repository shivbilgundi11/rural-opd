import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * Joins class names and resolves Tailwind conflicts, so a caller's `className`
 * can override a variant's without both ending up in the output and the winner
 * being decided by stylesheet order.
 *
 * `tailwind-merge` carries its own idea of Tailwind's default scales, which this
 * project has replaced — it will not know that `rounded-card` and
 * `rounded-input` conflict, so it keeps both and the later class wins by source
 * order. That is the correct outcome here anyway, and the alternative (teaching
 * it the custom scale) buys nothing until a primitive actually has two competing
 * radii.
 */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs));
}

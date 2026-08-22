import { cva, type VariantProps } from "class-variance-authority";
import { Loader2 } from "lucide-react";

import { motion } from "@rural-opd/tokens";

import { cn } from "@/lib/cn";
import { useReducedMotion } from "@/lib/use-reduced-motion";

import type { ButtonHTMLAttributes, ReactElement, ReactNode } from "react";

/**
 * DESIGN.md §4 — button press is a 100ms spring to scale 0.97.
 *
 * The spring numbers come from `motion.buttonPress` rather than being written
 * here, so the mobile `PressableScale` presses with exactly the same feel. CSS
 * has no spring, so the web side approximates it with a short transition on
 * `active:` — the shapes differ, the perceived duration does not, and
 * `docs/DESIGN-IMPLEMENTATION.md` records the pairing.
 *
 * The 44×44 floor from DESIGN.md §3 lives in the base variant, not at call
 * sites. §3 is explicit that tap areas must not be shrunk to fit more on screen,
 * and the reliable way to hold that line is to make the small version
 * unavailable rather than to catch it in review.
 */
const button = cva(
  [
    "inline-flex items-center justify-center gap-2",
    "rounded-card font-semibold",
    // DESIGN.md §3 — the floor, applied to every variant including icon-only.
    "min-h-touch min-w-touch",
    // DESIGN.md §2 — never below 14px for text a patient acts on.
    "text-base",
    "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2",
    // A disabled control still has to be readable; `opacity-50` on the AA-tuned
    // palette lands around 2.5:1, so the fill is swapped instead.
    "disabled:cursor-not-allowed disabled:bg-border-subtle disabled:text-text-muted",
  ].join(" "),
  {
    variants: {
      variant: {
        primary: "bg-primary-green text-text-on-fill hover:bg-accent-teal",
        secondary: "bg-primary-blue text-text-on-fill hover:bg-accent-teal",
        ghost: "bg-transparent text-primary-blue hover:bg-surface-alt",
        danger: "bg-danger text-text-on-fill hover:bg-danger",
      },
      size: {
        // Both clear 44px. `sm` is narrower, never shorter.
        sm: "px-3 py-2",
        md: "px-4 py-3",
      },
      fullWidth: { true: "w-full", false: "" },
    },
    defaultVariants: { variant: "primary", size: "md", fullWidth: false },
  },
);

type ButtonProps = ButtonHTMLAttributes<HTMLButtonElement> &
  VariantProps<typeof button> & {
    readonly children: ReactNode;
    /**
     * Disables the button and shows a spinner. Separate from `disabled` because
     * they mean different things to a screen reader: `busy` says "wait", and
     * `disabled` says "not available to you".
     */
    readonly loading?: boolean;
  };

export function Button({
  children,
  className,
  variant,
  size,
  fullWidth,
  loading = false,
  disabled,
  ...rest
}: ButtonProps): ReactElement {
  const reducedMotion = useReducedMotion();

  return (
    <button
      type="button"
      {...rest}
      disabled={disabled === true || loading}
      aria-busy={loading}
      className={cn(
        button({ variant, size, fullWidth }),
        // DESIGN.md §6 — an instant state change under reduced motion, not a
        // quicker animation. A 50ms scale is still a scale.
        reducedMotion ? "transition-none" : "transition-transform active:scale-press",
        className,
      )}
      style={
        reducedMotion
          ? undefined
          : // The one place a raw duration is legitimate: it is read from the
            // token, not written. `noInlineMotionTimings` allows this because it
            // is a member expression rather than a literal.
            { transitionDuration: `${motion.buttonPress.duration}ms` }
      }
    >
      {loading ? (
        <Loader2
          aria-hidden
          size={18}
          className={reducedMotion ? undefined : "animate-spin"}
        />
      ) : null}
      {children}
    </button>
  );
}

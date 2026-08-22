import { cva, type VariantProps } from "class-variance-authority";
import { ActivityIndicator, Text, View } from "react-native";

import { MIN_TOUCH_TARGET } from "@rural-opd/tokens";

import { PressableScale } from "@/components/ui/pressable-scale";
import { cn } from "@/lib/cn";

import type { ReactElement, ReactNode } from "react";

/**
 * The native twin of `apps/web/src/components/ui/button.tsx`. Same variants,
 * same tokens, same press spring — different implementation, which is exactly
 * what DESIGN.md §0 asks for.
 *
 * The variant class strings are intentionally near-identical to the web ones.
 * They are not shared, because NativeWind and Tailwind support different
 * subsets — `hover:` has no meaning on a touch screen and `active:` is handled
 * by the press spring rather than by a class — and a shared string that only
 * half applies on one surface is harder to reason about than two that each say
 * what they mean.
 */
const buttonClasses = cva(
  "flex-row items-center justify-center gap-2 rounded-card px-4 py-3",
  {
    variants: {
      variant: {
        primary: "bg-primary-green",
        secondary: "bg-primary-blue",
        ghost: "bg-transparent",
        danger: "bg-danger",
      },
      disabled: { true: "bg-border-subtle", false: "" },
      fullWidth: { true: "w-full", false: "self-start" },
    },
    defaultVariants: { variant: "primary", disabled: false, fullWidth: false },
  },
);

const labelClasses = cva("text-base font-semibold", {
  variants: {
    variant: {
      primary: "text-text-on-fill",
      secondary: "text-text-on-fill",
      ghost: "text-primary-blue",
      danger: "text-text-on-fill",
    },
    disabled: { true: "text-text-muted", false: "" },
  },
  defaultVariants: { variant: "primary", disabled: false },
});

type ButtonProps = VariantProps<typeof buttonClasses> & {
  readonly children: ReactNode;
  readonly onPress: () => void;
  readonly loading?: boolean | undefined;
  readonly className?: string | undefined;
  readonly accessibilityLabel?: string | undefined;
};

export function Button({
  children,
  onPress,
  variant,
  fullWidth,
  loading = false,
  disabled,
  className,
  accessibilityLabel,
}: ButtonProps): ReactElement {
  const isDisabled = disabled === true || loading;

  return (
    <PressableScale
      onPress={onPress}
      disabled={isDisabled}
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ disabled: isDisabled, busy: loading }}
      // DESIGN.md §3 — the floor, from the token rather than a literal.
      style={{ minHeight: MIN_TOUCH_TARGET, minWidth: MIN_TOUCH_TARGET }}
      className={cn(
        buttonClasses({ variant, disabled: isDisabled, fullWidth }),
        className,
      )}
    >
      {loading ? <ActivityIndicator size="small" /> : null}
      <View>
        <Text className={labelClasses({ variant, disabled: isDisabled })}>
          {children}
        </Text>
      </View>
    </PressableScale>
  );
}

/// <reference types="nativewind/types" />

// Teaches TypeScript that `className` is a valid prop on React Native
// components. Without it every `className` is a type error, and the usual
// reaction is to reach for `style` instead — which is how a screen ends up with
// hardcoded values that DESIGN.md §1 and §3 ban.

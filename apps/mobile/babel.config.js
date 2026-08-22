module.exports = function babelConfig(api) {
  api.cache(true);
  return {
    presets: [
      // `jsxImportSource: "nativewind"` is what routes JSX through NativeWind's
      // runtime so `className` means anything at all. NativeWind v4 does not
      // warn when it is missing — `className` is simply ignored, every screen
      // renders unstyled, and nothing in the output says why.
      [
        "babel-preset-expo",
        { jsxImportSource: "nativewind", unstable_transformImportMeta: true },
      ],
      "nativewind/babel",
    ],
    plugins: [
      // MUST stay last. The Reanimated (v4: worklets) plugin rewrites worklet
      // functions so they can run on the UI thread; a plugin ordered after it
      // can transform that output back into something the worklet runtime
      // rejects, and the failure is silent — animations fall back to the JS
      // thread and keep working.
      //
      // Which is exactly why it is dangerous. On a development flagship
      // everything looks fine. PRD §8 targets mid-range Android, where a
      // JS-thread animation drops frames badly, and the gallery's frame probe
      // exists to catch this on a real device rather than in review.
      "react-native-worklets/plugin",
    ],
  };
};

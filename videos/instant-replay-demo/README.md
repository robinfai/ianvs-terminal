# Instant Replay Demo

Remotion video for the Ianvs Terminal Instant Replay product feature.

The composition is `InstantReplayDemo`:

- 1920x1080
- 30 fps
- 25 seconds
- Chinese product captions with English in-app UI

## Commands

```console
npm i
```

```console
npm run dev
```

```console
npm run render
```

The rendered MP4 is written to `out/instant-replay-demo.mp4`.

## Assets

Product screenshots live in `public/product` and are copied from the existing
Ianvs Terminal audit captures. The generated replay workspace shots are built in
`src/Composition.tsx`.

**English** | [简体中文](README_zh.md)

<br>

# Paper Reader (papertok-reader)

**Paper Reader** is a customized distribution based on **[Anx Reader](https://github.com/Anxcye/anx-reader)**, integrating:

- **PaperTok** (academic paper feed)
- Enhanced **AI chat** (Provider Center, thinking levels, conversation tree)
- **Multimodal chat attachments** (images + plain text files)
- **EPUB image analysis** (tap image → analyze with a multimodal model)
- In-reader **inline full-text translation** (immersive “translation below original”)

## Platform status (important)

- ✅ **Tested:** iOS (iPhone) + iPadOS (iPad)
- ⚠️ **Not yet tested in this repo:** Android / Desktop (macOS/Windows/Linux)

If you need stable multi-platform usage **right now**, it’s recommended to use the upstream project **Anx Reader**.
Android testing for Paper Reader is planned, but not validated yet.

## Documentation

- Product docs index: **[`docs/README.md`](./docs/README.md)**
- iOS install / signing / TestFlight: **[`docs/engineering/IOS_DEPLOY_zh.md`](./docs/engineering/IOS_DEPLOY_zh.md)**
- Identifiers source of truth (Bundle ID / App Group / Android applicationId): **[`docs/engineering/IDENTIFIERS_zh.md`](./docs/engineering/IDENTIFIERS_zh.md)**

## Quick start (development)

```bash
flutter pub get
flutter gen-l10n
# repo ignores generated outputs; run build_runner when needed
# dart run build_runner build --delete-conflicting-outputs
flutter test -j 1
```

> Tip: if you run into SDK mismatch errors with build_runner, try:
> `flutter pub run build_runner build --delete-conflicting-outputs`

## Screenshots

![](./docs/images/main.jpg)

## Relationship to upstream

This repository focuses on **product distribution + PaperTok integration + iOS-first QA**.

Upstream contribution is currently **not required for product delivery**. If/when we decide to upstream generic AI/translation improvements later, we will do it via a clean contrib track (without PaperTok/product-only UX changes).

## License

MIT (same as upstream Anx Reader for the parts we build upon).
See [LICENSE](./LICENSE).

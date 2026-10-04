# Changelog

## 2.6.1 — 2026-10-05

- Publish the complete MIT-licensed source, original artwork, locales and Windows portable package.
- Isolate preview, smoke and animation checks from real Codex sessions, local preferences, stop signals and the normal single-instance mutex.
- Exercise three synthetic sessions during UI smoke checks; make optional local catalog tests explicitly opt-in.
- Recover current-session usage monitoring after temporary file locks, deletion and recreation. Clear stale metrics when selection is removed.
- Fail animation checks when any action misses frames; add diagnostic isolation and follow-helper checks to Windows CI.
- Check version syntax, required runtime/animation files and excluded private file types before building the portable ZIP; include a VERSION file and SHA256 checksum.

Existing behavior retained: 16 GIF actions, four languages, local usage/history estimates, scaling, session selection and the documented follow-Codex launcher helper.

## 2.6.0 — initial local baseline

Animated desktop companion, local session/history usage, four interface languages, original artwork and build/test scripts. The local source snapshot existed before the complete source was uploaded to the public repository.

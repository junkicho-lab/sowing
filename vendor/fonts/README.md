# Bundled Fonts

This directory contains TrueType fonts used by `Sowing::Output::PdfRenderer`
for Korean text rendering in PDF exports.

## Pretendard

- **Source**: https://github.com/orioncactus/pretendard
- **Version**: 1.3.9
- **License**: SIL Open Font License 1.1 (OFL-1.1)
- **Files**:
  - `Pretendard-Regular.ttf` (~2.7 MB)
  - `Pretendard-Bold.ttf` (~2.6 MB)

Pretendard is a modern Korean sans-serif font designed by 길성주 (Kil Seongju).
It supports Hangul + Latin + extended punctuation, with consistent metrics
between scripts — ideal for mixed Korean/English documents like 생기부·상담부.

### Override

Users can override the bundled fonts via environment variables:

```bash
export SOWING_PDF_FONT=/path/to/your/regular.ttf
export SOWING_PDF_FONT_BOLD=/path/to/your/bold.ttf  # optional
```

See `lib/sowing/output/font_config.rb` for the full lookup order.

### Why bundled

Korean PDF rendering requires an embedded TrueType font (Prawn's default
Helvetica is ASCII-only — Korean glyphs become `\uXXXX` placeholders).
System fonts (e.g., macOS `AppleGothic.ttf`) have malformed OS/2 tables that
crash ttfunk's subset encoder, so bundling a known-good font is the most
reliable approach for cross-platform reproducibility.

The total weight of ~5 MB is the cost of "it just works" for the primary
use case (Korean teacher's documents).

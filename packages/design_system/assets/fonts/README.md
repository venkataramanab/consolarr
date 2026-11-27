<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
# Bundled fonts

`Inter-Regular.ttf` and `Inter-Bold.ttf` are Inter (SIL OFL 1.1, see
`OFL.txt`), **subset to Latin**: Basic Latin, Latin-1, Latin Extended A/B,
IPA extensions, Latin Extended Additional (all of the en_XA pseudo-locale),
general punctuation, currency, arrows and a few math symbols. Arabic and other
scripts fall back to the system fonts. All OpenType layout features are kept
(tabular figures are used for speeds and sizes).

Regenerate from the upstream static TTFs with fontTools:

```sh
pyftsubset Inter-Regular.ttf \
  --unicodes="U+0020-007E,U+00A0-024F,U+0250-02AF,U+02C6,U+02DA,U+02DC,U+1E00-1EFF,U+2010-2015,U+2018-201E,U+2020-2022,U+2026,U+2030,U+2032-2033,U+2039-203A,U+2044,U+20AC,U+2122,U+2190-2193,U+2212,U+2215,U+2248,U+2260,U+2264-2265,U+25CF" \
  --layout-features='*' --output-file=Inter-Regular.ttf
```

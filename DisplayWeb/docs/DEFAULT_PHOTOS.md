# Default photos

Default web order: `01` → `08`. The high-resolution copies are retained outside `public/` under `assets/photos/source/`; the website loads only the web derivatives in `public/photos/`.

| # | Source copy | Source px | Web derivative | Web px | Web bytes | Web SHA256 |
|---|---|---:|---|---:|---:|---|
| 1 | `default-20261031-01-original.jpg` | 1080x602 | `default-20261031-01.jpg` | 1080x602 | 74849 | 7BEC09BD25D299E89033A98D3B27CD20AB1936ED883CF1B1E891692B1115A2FA |
| 2 | `default-20261031-02-original.jpg` | 1674x952 | `default-20261031-02.jpg` | 1674x952 | 127227 | F421D3FC51F85316B7F7ECD2404B3F30B70AFAE80FE37766D3D6092C59EF5E5E |
| 3 | `default-20261031-03-original.jpg` | 1080x592 | `default-20261031-03.jpg` | 1080x592 | 201897 | A04B8182496F777AEDC55C92F24B6A0E8C17920EBBBFBAF2255D86AA35B593A6 |
| 4 | `default-20261031-04-original.jpg` | 1876x1060 | `default-20261031-04.jpg` | 1876x1060 | 273163 | F4208D89FFE2F284BAC2A41E20B31B1E208DEA4A7B1B00055DA7A2C706178218 |
| 5 | `default-20261031-05-original.jpg` | 1580x910 | `default-20261031-05.jpg` | 1580x910 | 196819 | F763464904DF950521C03522F614723645AF2872024E83BB82BA66544BAC93AC |
| 6 | `default-20261031-06-original.jpg` | 1564x902 | `default-20261031-06.jpg` | 1564x902 | 106379 | F7C5F9F6CAAAA142125029A94A139ED5D343B62D05FBF465C85B6FC983F5AAE4 |
| 7 | `default-20261031-07-original.jpg` | 1412x778 | `default-20261031-07.jpg` | 1412x778 | 66865 | 026C32720D36BFF3BD8DC5B298898390559B5ACAC01FF43FFCAE9933DBB5C76D |
| 8 | `default-20261031-08-original.jpg` | 1664x964 | `default-20261031-08.jpg` | 1664x964 | 50402 | C4E8ABFDC9BE08BD66849503CDC0B8A049790DA658F97E360ABA1D9BEDA59155 |

## Notes

- The old `photo-01.jpg`–`photo-03.jpg` defaults were removed from `public/photos/` and `dist/photos/`; the pre-change copy remains only in `backups/InstrumentDisplayWeb_pre_photo_refresh_20261031/`.
- Source `picture/` files were sorted by filename; the order is preserved as 01→08. Original files in the source folder were not deleted.
- New filenames include `20261031` to avoid stale browser image caches and HTTP cache entries.
- Web files are JPEG. No upscale was performed; all source widths were ≤1920 px and are preserved.
- `PhotoDeck.ts` is the ordered list; `PhotoDeck.loadDefaults()` loads all eight from page-local `./photos/` URLs.
- The runtime does not reference `GowinProjects`, `text4`, `picture`, `file://`, symlinks, or the source folder.
- One-time migration marker: `instrument-display-default-photo-set=20261031-v1`; old photo index keys, `photoOffset`, and carousel interval are cleared once.
- Manual `#photoInput` imports remain supported and are appended in-session.

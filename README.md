# QRCode Barrel

A Garmin Connect IQ barrel (library) for generating and rendering QR codes on-device. Pure Monkey C — no network calls, no external services.

- **Module:** `QRCode`
- **Min API level:** 3.2.0
- **Version:** 1.0.0

## Features

- **On-device QR generation.** Encodes a string to a QR matrix entirely on the watch / Edge device.
- **Reed-Solomon error correction.** All four levels supported: `L` (7%), `M` (15%), `Q` (25%), `H` (30%).
- **Two encoder variants:**
  - `Encoder` — synchronous, single-call encoding. Best for fast devices.
  - `EncoderChunked` — splits the work across `Timer` ticks (50 ms chunks) so slow devices don't trip the Connect IQ watchdog.
- **Renderer with bitmap caching.** Uses `BufferedBitmap` (or `BufferedBitmapReference` on API ≥ 4.0) so the O(n²) module draw only happens when the data, size, or colors change — subsequent frames are a single blit.
- **Round-screen aware.** Renderer fits the QR inside the inscribed square on round displays and centers it automatically.
- **Configurable colors** via `Renderer.setColors(fg, bg)`.
- **Optional label** below the code via `Renderer.drawWithLabel(dc, label)`.
- **Wide device coverage.** The barrel declares ~130 products — Forerunner, Fenix, Epix, Edge, Venu, Vivoactive, Approach, Descent, Instinct, MARQ, D2, and more (see `manifest.xml`).

## Limitations

- **Alphanumeric mode only.** Input is uppercased and must consist of `0-9`, `A-Z`, space, or `$%*+-./:`. No byte mode, no UTF-8, no Kanji. URLs that need lowercase characters won't fit.
- **Versions 1–3 only.** That's 21×21, 25×25, or 29×29 modules. Capacity caps out at ~84 alphanumeric characters (V3, level L). Longer payloads will not encode.
- **Fixed mask pattern.** Mask 5 is hard-coded — the encoder does not run the standard penalty-score search to pick the optimal mask. In practice scanners read it fine, but it isn't strictly spec-optimal.
- **Quiet zone is 1 module**, not the spec-recommended 4, to maximise usable area on small displays. Scanners have been observed to handle this without issue but it is non-standard.
- **Consuming apps must restrict their supported device list.** The barrel ships with the full device list, but any app depending on it has to narrow `<iq:products>` in its own `manifest.xml` to the devices it actually targets (the Connect IQ compiler will not auto-intersect).
- **No raw bitmap export.** The renderer draws to a `Dc`; there is no API to extract the matrix as a PNG or external image.

## Using the barrel

### 1. Add the dependency

In your app's `barrels.jungle`:

```
QRCode = [/path/to/qr-code-barrel/barrel.jungle]
base.barrelPath = $(base.barrelPath);$(QRCode)
```

In your app's `manifest.xml`:

```xml
<iq:barrels>
    <iq:depends name="QRCode" version="1.0.0"/>
</iq:barrels>
```

Make sure your app's `<iq:products>` list is restricted to devices you actually support.

### 2. Simple (synchronous) usage

Good for newer devices where encoding completes well inside one event loop tick.

```monkeyc
using QRCode;

var encoder = new QRCode.Encoder(2, QRCode.Encoder.ERROR_LEVEL_L);
if (encoder.encode("HELLO 123")) {
    var renderer = new QRCode.Renderer(encoder);
    renderer.setColors(Graphics.COLOR_BLACK, Graphics.COLOR_WHITE);
    renderer.calculateLayout(dc);
    renderer.draw(dc);
    // or: renderer.drawWithLabel(dc, "HELLO 123");
}
```

### 3. Chunked (asynchronous) usage

Recommended on older / slower devices (e.g. fr245) to avoid watchdog timeouts. The encoder progresses one state per timer tick and invokes your callback when done.

```monkeyc
using QRCode;

var chunked = new QRCode.EncoderChunked();
chunked.startEncode(
    "HELLO 123",
    2,                              // version 1-3
    QRCode.Encoder.ERROR_LEVEL_L,
    method(:onEncodeComplete)       // callback
);

function onEncodeComplete(encoder as QRCode.Encoder?) as Void {
    if (encoder != null) {
        mRenderer = new QRCode.Renderer(encoder);
        WatchUi.requestUpdate();
    }
}
```

See `examples/qr-app/` for a complete standalone watch-app that uses the chunked encoder, handles the "Encoding…" loading state, and re-renders on layout changes.

### Public API summary

`QRCode.Encoder`
- `new Encoder(version, errorLevel)` — version 1–3, `ERROR_LEVEL_L|M|Q|H`
- `encode(data as String) as Boolean` — returns `false` if input isn't alphanumeric or doesn't fit
- `getMatrix()`, `getSize()`

`QRCode.EncoderChunked`
- `startEncode(data, version, errorLevel, callback)`
- `stopEncode()`, `isEncoding()`, `isComplete()`, `getEncoder()`

`QRCode.Renderer`
- `new Renderer(encoder)`
- `setColors(fg, bg)` — invalidates the cached bitmap if changed
- `calculateLayout(dc)` — call before the first draw and whenever screen size changes
- `draw(dc)`, `drawWithLabel(dc, label)`
- `invalidateCache()` — call after replacing the QR data

## Building

The `Makefile` at the repo root builds the example app and runs tests:

```
make build       # build the example data-field
make run         # build + launch in the simulator (PRODUCT=fr255 by default)
make test        # run the unit tests under test/
```

Override `PRODUCT=...` to target a different device, e.g. `make run PRODUCT=vivoactive5`.

# Chrome Native Messaging Setup

Chrome requires the final unpacked extension ID in the native host manifest.

1. Build once with `./script/build_and_run.sh --verify`.
2. Open `chrome://extensions`.
3. Enable Developer Mode.
4. Load unpacked extension from `chrome-extension/`.
5. Copy the extension ID.
6. Confirm `allowed_origins` in `native-host/com.arel.focus.bridge.json` matches that ID.
7. Confirm `path` points at the built `dist/ArelFocusNativeBridge` for the active checkout.
8. Build and install the manifest:

```bash
./script/build_and_run.sh --install-bridge
```

Set `AREL_FOCUS_EXTENSION_ID=<id>` before running the command if Chrome gives the
unpacked extension a different ID.

The native host writes Chrome tab events to:

```text
~/Library/Application Support/Arel Focus/chrome-events.jsonl
```

## Multiple Chrome Profiles

Chrome profiles run separate extension instances. To track another profile, open
that profile's `chrome://extensions` page and load this same unpacked
`chrome-extension/` folder there too.

Each profile gets a local generated profile ID through `chrome.storage.local`.
Arel Focus persists that ID on active and open tab sessions so windows/tabs from
different profiles do not merge together.

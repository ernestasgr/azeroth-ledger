# Settings customization

The native AddOns Settings category now has Appearance, Notifications, and Tooltips pages. The main page keeps window/browsing resets, Journal retention, and developer mode.

Appearance includes nine native color swatches, ten theme presets, window scale, background opacity, position locking, reduced motion, and item-quality colors. Palette changes repaint existing regions through their color roles. Transparent backgrounds leave text opaque. High Contrast restores an opaque background. The additional presets are Alliance Blue, Horde Crimson, Druid Grove, Arcane Violet, Fel Green, Parchment, and Midnight. Parchment uses dark ink for item names and notifications; players can re-enable quality colors. Notification settings cover size, duration, position, discovery sound, combat pauses, and a sample preview. Tooltips can omit dated storage checks while retaining status, totals, and source.

Preferences are account-wide and saved through the store. Missing fields use defaults; invalid fields fall back independently. Reads copy color arrays, writes validate and copy them, and unsupported ledger schemas reject changes. Appearance and notification resets preserve Collection and Journal facts. Existing Journal retention controls remain explicit about removing older rows.

## Automated evidence

- `tests/settings_spec.lua`: native registration, nine color controls, live repainting and picker cancellation values, theme presets, text contrast across each new palette, independent resets, movement locking, reduced motion, opacity, scale, reload restoration, corrupt values, immutable reads, and unsupported schema protection.
- `tests/presentation_spec.lua`: duration, sound, combat pause/resume, muted preview, preview dismissal, and notification screen bounds.
- `AzerothLedgerCollection.AppearancePreferencesPersistAndKeepCollectionFacts`: persisted appearance preferences and unchanged Collection quantities, also exercised by the host WoWUnit replay.
- Lua 5.1 syntax and all 22 host behavior specs passed, including the 10,000-item performance regression. Luacheck, StyLua, LuaLS, package validation, and all three installer behavior tests passed locally. Windows path-resolution checks required execution outside the filesystem sandbox.
- The installed account SavedVariables were verified as healthy schema 2 before installation. The Forever beta flavor and installed-file SHA-256 hashes were verified; SavedVariables and WoWUnit files were preserved.

The Settings and color-swatch interfaces were checked against the local `wow-ui-source` checkout and installed Forever `BlizzardInterfaceCode`. [Blizzard Settings implementation reference](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua).

## Pending native checks

The Forever client could not be exercised in this environment. Build, locale, actual native WoWUnit results, and Lua-error status remain unrecorded for this implementation; host replay and installation hashes do not establish these results.

In the Forever client, open AddOns Settings → Azeroth Ledger. Test all three pages, custom colors and picker Cancel, resets, both notification preview and an actual discovery, sound, combat pause/resume, window locking, and changes to UI scale. Run AzerothLedgerCollection and AzerothLedgerPresentation in WoWUnit. Verify preferences and item facts after `/reload` and a full exit/relaunch, and record build, locale, test results, and Lua errors.

# HiBy R1 AutoEq

A native AutoEq integration plugin for the **HiBy R1 / open_hiby_player** that brings AutoEq IEM headphone measurements directly into the player's built-in 10-band parametric EQ.

The plugin is designed around the R1's lightweight environment: the large AutoEq catalog stays on the SD card, while only the selected profile is loaded into memory and applied through the native EQ API.

## Features

- Search the AutoEq measurement database directly from the HiBy R1.
- Select an IEM/measurement and apply its AutoEq parametric EQ curve.
- Applies the profile directly to the R1's native PEQ engine.
- Supports AutoEq parametric filters including peaking, low-shelf, and high-shelf filters.
- Saves selected profiles as native `.peq` files for fast offline reuse.
- Re-open previously downloaded profiles from **Saved Configs**.
- Remove downloaded/cached configurations directly from the R1.
- Shows the currently active IEM/profile in **Current Config**.
- Keeps the AutoEq database and cached profiles on the SD card instead of filling plugin RAM.
- Persists the selected AutoEq profile across reboot.
- Can return the EQ to a flat/default state.

## How It Works

The plugin uses the R1's native EQ interface rather than implementing a second DSP layer.

```text
AutoEq database
      │
      ▼
 Search IEM / measurement
      │
      ▼
 Download ParametricEQ.txt
      │
      ▼
 Parse AutoEq filters
      │
      ▼
 Native R1 PEQ
  ┌─────────────────────┐
  │ Preamp              │
  │ Band 1              │
  │ Band 2              │
  │ ...                 │
  │ Band 10             │
  └─────────────────────┘
      │
      ▼
 Save native .peq profile
      │
      ▼
 Available offline in Saved Configs
```

This follows the same native EQ approach demonstrated by the project's `SoundProfiles.lua`: configure the ten native bands, enable/disable the required bands, save the profile, and load it again when needed.

## Repository Structure

The repository contains the complete set of Lua plugins developed for the HiBy R1 / open_hiby_player environment. Each plugin is a standalone `.lua` file and is installed directly into the R1 SD card's `.plugins` directory.

```text
.
├── .plugins/
│   ├── AutoEq.lua
│   ├── GainMode.lua
│   ├── LastFmScrobbler.lua
│   ├── LockScreen.lua
│   ├── PlayThrough.lua
│   ├── SoundProfiles.lua
│   └── Themes.lua
├── README.md
└── LICENSE
```

### Plugin Files

| File | Purpose |
|---|---|
| `AutoEq.lua` | AutoEq IEM profile search, download, native 10-band PEQ application, caching, saved-config management, and persistent current configuration. |
| `GainMode.lua` | Gain-mode control for switching between the available playback gain settings. |
| `LastFmScrobbler.lua` | Last.fm scrobbling with persistent offline queue support so tracks can be uploaded when connectivity returns. |
| `LockScreen.lua` | Custom lock-screen behavior and album-art/clock presentation. |
| `PlayThrough.lua` | Automatic playback continuation between albums/folders when a track or album finishes. |
| `SoundProfiles.lua` | Native EQ profile switcher using the R1's built-in 10-band PEQ engine. |
| `Themes.lua` | Custom theme selection and visual customization for the player UI. |

All plugin files are intended to live directly under `SD/.plugins/`. The plugin manager discovers Lua plugins from this directory.

### Installation Layout

```text
SD/
├── .plugins/
│   ├── AutoEq.lua
│   ├── GainMode.lua
│   ├── LastFmScrobbler.lua
│   ├── LockScreen.lua
│   ├── PlayThrough.lua
│   ├── SoundProfiles.lua
│   └── Themes.lua
│
└── AutoEq/
    ├── INDEX.md
    ├── RANKING.md
    ├── Profiles/
    │   ├── <saved IEM profile>.peq
    │   ├── <saved IEM profile>.txt
    │   └── ...
    └── Imports/
        └── <optional local ParametricEQ.txt files>
```

`AutoEq/` is created and populated only when the AutoEq plugin is used. The other plugins keep their own small state/configuration data under `.plugins/` as required by their implementation.

## SD Card Runtime Structure

After installation and use, the plugin creates its working data on the SD card.

```text
SD/
├── .plugins/
│   └── AutoEq.lua
│
└── AutoEq/
    ├── INDEX.md
    ├── RANKING.md
    ├── Profiles/
    │   ├── <saved IEM profile>.peq
    │   ├── <saved IEM profile>.txt
    │   └── ...
    │
    └── Imports/
        └── <optional local ParametricEQ.txt files>
```

The exact cached profile filenames are generated from the AutoEq measurement/model path so that different measurements of the same IEM can coexist.

The AutoEq catalog is kept on the SD card and is not bundled into the Lua plugin. This keeps the plugin package lightweight and avoids loading the complete database into the R1's limited RAM.

## Installation

1. Download the latest release ZIP.
2. Extract `AutoEq.lua`.
3. Copy it to:

```text
SD/.plugins/AutoEq.lua
```

4. Restart the HiBy R1, or use the firmware's **Apply Plugin Changes** option if available.
5. Open the **AutoEq** entry from the plugin settings menu.
6. Use **Find & Apply IEM** to search for your IEM.

## Using AutoEq

### Find & Apply IEM

Search the downloaded AutoEq index, choose the desired IEM/measurement, and download its AutoEq `ParametricEQ.txt` profile.

The selected filter set is then translated into the R1's native ten-band PEQ and applied immediately.

### Saved Configs

Previously downloaded profiles can be loaded again without downloading them.

```text
AutoEq
└── Saved Configs
    └── Select profile
        └── Load native .peq
```

### Remove Saved Config

Downloaded configurations can be removed directly from the plugin.

Removing the active configuration also returns the EQ to the flat/default state and clears the active AutoEq selection.

### Current Config

Displays the IEM/measurement currently selected by AutoEq.

### Reset to Flat

Restores the R1's native EQ to its default flat state.

## Acknowledgements

Special thanks to **Starnished66** for creating the **R1-open-source-player** project, which made this work possible.

- GitHub: https://github.com/Starnished66
- R1-open-source-player: https://github.com/Starnished66/R1-open-source-player

## AutoEq Data

This project uses the measurement database and equalization methodology from:

**jaakkopasanen/AutoEq**

https://github.com/jaakkopasanen/AutoEq

Huge thanks to **Jaakko Pasanen** and the AutoEq project for the measurement processing, target handling, and parametric EQ ecosystem that makes this plugin possible.

> This plugin is an integration for the HiBy R1/open_hiby_player. AutoEq itself remains a separate project.

## Native R1 EQ Integration

The plugin uses the native PEQ functions exposed by the R1 plugin API:

```lua
plugin.eq_reset()
plugin.eq_set_preamp(db)
plugin.eq_set_band(index, freq_hz, gain_db, q)
plugin.eq_set_band_type(index, type)
plugin.eq_set_band_enabled(index, enabled)
plugin.eq_save_profile(path)
plugin.eq_load_profile(path)
```

Native `.peq` files are interchangeable with profiles created by the player's own EQ screen, allowing AutoEq configurations to live alongside normal R1 EQ profiles.

## Memory / Storage Design

The HiBy R1 is a very constrained embedded player, so the plugin deliberately avoids keeping the whole AutoEq database in Lua memory.

```text
Large database  ───────────────► SD card
Cached EQ files ───────────────► SD card
Selected profile ──────────────► Native R1 EQ
Persistent selection state ────► Plugin storage
```

Only small pieces of metadata and the selected profile are processed at a time.

## Compatibility

Designed for:

- HiBy R1
- open_hiby_player firmware/plugin system
- Native 10-band parametric EQ exposed through the plugin API

The plugin expects the R1 plugin API to provide the EQ and SD-card functions used by `AutoEq.lua`.

## Development

The repository is organized as a small collection of independent Lua plugins:

```text
.plugins/
├── AutoEq.lua
│   ├── AutoEq index/search
│   ├── HTTP/download handling
│   ├── ParametricEQ.txt parsing
│   ├── Native PEQ application
│   ├── Profile caching
│   ├── Saved Config management
│   └── Persistent current-config state
├── GainMode.lua
├── LastFmScrobbler.lua
├── LockScreen.lua
├── PlayThrough.lua
├── SoundProfiles.lua
└── Themes.lua
```

When modifying the plugin suite, keep large datasets off the Lua heap and prefer the provided SD-card, asynchronous network, and native EQ APIs where applicable.

When modifying the plugin, keep large datasets off the Lua heap and prefer the provided asynchronous/network and filesystem APIs for SD-backed operations.

## Credits

### AutoEq

Special thanks to the AutoEq project:

https://github.com/jaakkopasanen/AutoEq

AutoEq provides the core measurement/equalization data used by this plugin.

### HiBy R1 / open_hiby_player

Built for the open plugin system of the HiBy R1/open_hiby_player ecosystem and its native PEQ APIs.

## License

See the repository's `LICENSE` file for the license of this plugin. AutoEq is a separate upstream project with its own licensing and attribution terms.

---

**Current plugin release:** `v1.3.5`

**Main file:** `.plugins/AutoEq.lua`

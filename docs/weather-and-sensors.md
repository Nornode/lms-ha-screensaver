# Weather Glyphs, Sensors & Per-Radio Overrides

## Weather Glyphs (All 15 Home Assistant Conditions)

Enter any Home Assistant `weather.*` entity (e.g., `weather.home`) in **Weather Entity ID** to show a live weather glyph:
- **Landscape (`320×240` Radio, `480×272` Touch, Jivelite)**: Centered between sensor columns in the bottom band.
- **Portrait (`240×320` Controller)**: Centered above the divider between the clock and sensor rows.
- **Sizing**: Defaults to **Large** (native `56×56` 4× supersampled anti-aliased PNGs) with an optional **Compact** (`44×44`) mode in Appearance settings.
- **Light & Dark Icons**: Every condition ships in both standard (dark-background) and dark-ink (`*_dark.png`, used automatically with the **Bright Silver** theme) variants.

All **15 official Home Assistant `weather.*` states** have dedicated glyphs:

| Dark BG | Light BG (Silver) | Home Assistant State | Alias(es) | Icon Key | Description |
| :---: | :---: | :--- | :--- | :--- | :--- |
| <img src="../radio-applet/HAScreenSaver/weather_sunny.png" alt="sunny" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_sunny_dark.png" alt="sunny (light bg)" width="36" height="36" /> | `sunny` | `clear` | `sunny` | Golden sun with 8 rays |
| <img src="../radio-applet/HAScreenSaver/weather_clear_night.png" alt="clear-night" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_clear_night_dark.png" alt="clear-night (light bg)" width="36" height="36" /> | `clear-night` | — | `clear_night` | Crescent moon with stars |
| <img src="../radio-applet/HAScreenSaver/weather_partlycloudy.png" alt="partlycloudy" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_partlycloudy_dark.png" alt="partlycloudy (light bg)" width="36" height="36" /> | `partlycloudy` | `partly-cloudy` | `partlycloudy` | Sun peeking behind cloud |
| <img src="../radio-applet/HAScreenSaver/weather_cloudy.png" alt="cloudy" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_cloudy_dark.png" alt="cloudy (light bg)" width="36" height="36" /> | `cloudy` | `overcast` | `cloudy` | Layered clouds |
| <img src="../radio-applet/HAScreenSaver/weather_rainy.png" alt="rainy" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_rainy_dark.png" alt="rainy (light bg)" width="36" height="36" /> | `rainy` | `rain` | `rainy` | Cloud with rain drops |
| <img src="../radio-applet/HAScreenSaver/weather_pouring.png" alt="pouring" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_pouring_dark.png" alt="pouring (light bg)" width="36" height="36" /> | `pouring` | — | `pouring` | Dark cloud with heavy downpour |
| <img src="../radio-applet/HAScreenSaver/weather_hail.png" alt="hail" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_hail_dark.png" alt="hail (light bg)" width="36" height="36" /> | `hail` | — | `hail` | Dark cloud with hail pellets |
| <img src="../radio-applet/HAScreenSaver/weather_snowy.png" alt="snowy" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_snowy_dark.png" alt="snowy (light bg)" width="36" height="36" /> | `snowy` | `snow` | `snowy` | Cloud with snowflakes |
| <img src="../radio-applet/HAScreenSaver/weather_snowy_rainy.png" alt="snowy-rainy" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_snowy_rainy_dark.png" alt="snowy-rainy (light bg)" width="36" height="36" /> | `snowy-rainy` | — | `snowy_rainy` | Cloud with mixed rain and snow |
| <img src="../radio-applet/HAScreenSaver/weather_fog.png" alt="fog" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_fog_dark.png" alt="fog (light bg)" width="36" height="36" /> | `fog` | `mist` | `fog` | Cloud with horizontal mist bars |
| <img src="../radio-applet/HAScreenSaver/weather_lightning.png" alt="lightning" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_lightning_dark.png" alt="lightning (light bg)" width="36" height="36" /> | `lightning` | — | `lightning` | Dark cloud with lightning bolt |
| <img src="../radio-applet/HAScreenSaver/weather_lightning_rainy.png" alt="lightning-rainy" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_lightning_rainy_dark.png" alt="lightning-rainy (light bg)" width="36" height="36" /> | `lightning-rainy` | — | `lightning_rainy` | Dark cloud with lightning bolt & rain |
| <img src="../radio-applet/HAScreenSaver/weather_windy.png" alt="windy" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_windy_dark.png" alt="windy (light bg)" width="36" height="36" /> | `windy` | — | `windy` | Wind gusts |
| <img src="../radio-applet/HAScreenSaver/weather_windy_variant.png" alt="windy-variant" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_windy_variant_dark.png" alt="windy-variant (light bg)" width="36" height="36" /> | `windy-variant` | — | `windy_variant` | Cloud with wind gusts |
| <img src="../radio-applet/HAScreenSaver/weather_exceptional.png" alt="exceptional" width="36" height="36" /> | <img src="../radio-applet/HAScreenSaver/weather_exceptional_dark.png" alt="exceptional (light bg)" width="36" height="36" /> | `exceptional` | — | `exceptional` | Weather alert warning triangle |

---

## Live Sensors (Up to 4 Slots)

Configure 1 to 4 entities under **Home Assistant Sensors — Global Defaults**:

- **Numeric sensors** (`sensor.*`): Rounded to configured decimals (`0`–`4`), using Home Assistant's `unit_of_measurement` unless a custom unit override is set.
- **Binary & categorical entities** (`binary_sensor.*`, `lock.*`, `cover.*`, `person.*`): Automatically localized via Home Assistant's `state_translated()` (HA 2024.3+, with built-in English `device_class` fallback) so doors show *Open/Closed*, locks show *Locked/Unlocked*, etc.
- **Adaptive layouts**:
  - **Landscape**: 1–2 sensors flank the weather glyph; 3–4 sensors use 1 row on widescreen (`480×272`) or a 2×2 grid on `320×240`.
  - **Portrait (`240×320`)**: 1 sensor centers full-width; 2 sensors stack as full-width horizontal rows; 3–4 sensors use a 2×2 grid.
- **Optional Alert / Door Banner**: Displays an alert pill with a door icon in the top-left corner **only** when active (automatically hidden when `off`, `closed`, `none`, `ok`, or empty).

---

## Per-Radio Overrides

Customize any individual radio without affecting others:

- **Classic LMS Skin**: **Settings → Player → [Select Radio] → Home Assistant Screensaver**
- **Material Skin**: **Settings → Player Settings → [Radio] → Extra Settings → Home Assistant Screensaver**

Rules for every player override:
1. **Leave blank / Use Global Default** → inherits the Global Default.
2. **Enter an Entity ID / choose an option** → overrides that item for this radio only.
3. **Enter `none`** (for weather, alert, or sensor slots) → hides a Global Default on this radio.
4. **Reset Overrides** → clears all custom settings on this radio in one click.

*Squeezebox Controller (`jive`)* automatically follows the currently selected player's overrides and alarm status, falling back to Global Defaults if no player is selected.

---

## Optional: Instant Refresh from Home Assistant Automations

Push an immediate screensaver refresh (e.g., when a door opens) via LMS JSON-RPC:

```yaml
rest_command:
  lms_screensaver_refresh:
    url: "http://<YOUR_LMS_HOST>:9000/jsonrpc.js"
    method: POST
    content_type: "application/json"
    payload: '{"id":1,"method":"slim.request","params":["",["hascreensaver","refresh"]]}'
```

# AirCardIcon layers

The app icon is authored as `Resources/AirCardIcon.icon`, the multilayer
Icon Composer format used by current Xcode releases. Its layers are deliberately
simple and solid so Icon Composer can apply Liquid Glass dynamically:

1. deep cobalt capsule;
2. cyan/violet refraction rim;
3. white card body;
4. blue card stripe;
5. blue card slot.

The Swift Package build also renders a deterministic vector fallback and packs
it as `AirCardMac.icns` for older macOS and direct bundle builds. No raster
concept art is used by the app.

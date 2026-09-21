# AirCardIcon layers

The app icon is authored as `Resources/AirCardIcon.icon`, the multilayer
Icon Composer format used by current Xcode releases. Its layers are deliberately
simple and solid so Icon Composer can apply Liquid Glass dynamically:

1. deep cobalt capsule;
2. cyan/violet refraction rim;
3. white card body;
4. blue card stripe;
5. blue card slot.

Xcode 26.2 compiles this source into `Resources/Assets.car` and
`Resources/AirCardIcon.icns`. The app bundle uses those compiled artifacts;
there is no hand-rendered concept PNG in the icon pipeline.

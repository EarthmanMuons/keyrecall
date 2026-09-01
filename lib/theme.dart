import 'package:material_ui/material_ui.dart';

/// The seed the KeyRecall palette is generated from.
const seedColor = Color(0xFFFFA500);

/// The KeyRecall palette, pinned.
///
/// These schemes are the Material 2025 color spec in the Neutral
/// style, grown from [seedColor]. That spec lives in Google's
/// material-color-utilities, but only in its Java, Kotlin, and
/// TypeScript ports; the Dart port implements the 2021 spec alone, so
/// [ColorScheme.fromSeed] cannot produce these colors. They were generated at
/// <https://materialkolor.com/?color_seed=FFFFA500&style=Neutral&color_spec=SPEC_2025>
/// and transcribed here.
///
/// Being literal, they ignore [ThemeData.brightness] tinting and cannot answer
/// to a contrast level. Regenerate both schemes from that URL if the seed
/// changes, and delete this file in favor of a seeded scheme once the Dart
/// color utilities support the 2025 spec.
///
/// Roles Flutter has no place for are left off. `background`, `onBackground`,
/// and `surfaceVariant` are deprecated here and repeat `surface`, `onSurface`,
/// and `surfaceContainerHighest`. The generator's `ControlActivated`,
/// `ControlNormal`, `ControlHighlight`, and `TextPrimaryInverse` family are
/// Android framework theme attributes, and the `PaletteKeyColor` values are the
/// tonal palette keys the spec derives these roles from, not roles.
const lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF855400),
  onPrimary: Color(0xFFFFF6F0),
  primaryContainer: Color(0xFFFFDDB7),
  onPrimaryContainer: Color(0xFF734800),
  primaryFixed: _primaryFixed,
  primaryFixedDim: _primaryFixedDim,
  onPrimaryFixed: _onPrimaryFixed,
  onPrimaryFixedVariant: _onPrimaryFixedVariant,
  secondary: Color(0xFF645E58),
  onSecondary: Color(0xFFFFF7F3),
  secondaryContainer: Color(0xFFEBE1D9),
  onSecondaryContainer: Color(0xFF57514B),
  secondaryFixed: _secondaryFixed,
  secondaryFixedDim: _secondaryFixedDim,
  onSecondaryFixed: _onSecondaryFixed,
  onSecondaryFixedVariant: _onSecondaryFixedVariant,
  tertiary: Color(0xFF695F38),
  onTertiary: Color(0xFFFFF8EC),
  tertiaryContainer: Color(0xFFF7E8B7),
  onTertiaryContainer: Color(0xFF5F552F),
  tertiaryFixed: _tertiaryFixed,
  tertiaryFixedDim: _tertiaryFixedDim,
  onTertiaryFixed: _onTertiaryFixed,
  onTertiaryFixedVariant: _onTertiaryFixedVariant,
  error: Color(0xFF9E422C),
  onError: Color(0xFFFFF7F6),
  errorContainer: Color(0xFFFE8B70),
  onErrorContainer: Color(0xFF742410),
  surface: Color(0xFFFEF8F5),
  onSurface: Color(0xFF36322E),
  onSurfaceVariant: Color(0xFF635E59),
  surfaceDim: Color(0xFFE1D8D2),
  surfaceBright: Color(0xFFFEF8F5),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF9F2EE),
  surfaceContainer: Color(0xFFF4ECE8),
  surfaceContainerHigh: Color(0xFFEFE7E1),
  surfaceContainerHighest: Color(0xFFE9E1DB),
  surfaceTint: Color(0xFF855400),
  inverseSurface: Color(0xFF0F0E0C),
  onInverseSurface: Color(0xFFA09C99),
  inversePrimary: Color(0xFFFFA504),
  outline: Color(0xFF807A75),
  outlineVariant: Color(0xFFB8B1AB),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

/// The dark rendering of [lightColorScheme]; see it for provenance.
const darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFFFB95C),
  onPrimary: Color(0xFF5C3800),
  primaryContainer: Color(0xFF653E00),
  onPrimaryContainer: Color(0xFFFFC67F),
  primaryFixed: _primaryFixed,
  primaryFixedDim: _primaryFixedDim,
  onPrimaryFixed: _onPrimaryFixed,
  onPrimaryFixedVariant: _onPrimaryFixedVariant,
  secondary: Color(0xFFA59C95),
  onSecondary: Color(0xFF241F1B),
  secondaryContainer: Color(0xFF403A35),
  onSecondaryContainer: Color(0xFFC7BEB6),
  secondaryFixed: _secondaryFixed,
  secondaryFixedDim: _secondaryFixedDim,
  onSecondaryFixed: _onSecondaryFixed,
  onSecondaryFixedVariant: _onSecondaryFixedVariant,
  tertiary: Color(0xFFFFF6DF),
  onTertiary: Color(0xFF675D37),
  tertiaryContainer: Color(0xFFF7E8B7),
  onTertiaryContainer: Color(0xFF5F552F),
  tertiaryFixed: _tertiaryFixed,
  tertiaryFixedDim: _tertiaryFixedDim,
  onTertiaryFixed: _onTertiaryFixed,
  onTertiaryFixedVariant: _onTertiaryFixedVariant,
  error: Color(0xFFED7F64),
  onError: Color(0xFF450900),
  errorContainer: Color(0xFF7E2B17),
  onErrorContainer: Color(0xFFFF9B82),
  surface: Color(0xFF0F0E0C),
  onSurface: Color(0xFFECE4DE),
  onSurfaceVariant: Color(0xFFB1AAA4),
  surfaceDim: Color(0xFF0F0E0C),
  surfaceBright: Color(0xFF302B27),
  surfaceContainerLowest: Color(0xFF000000),
  surfaceContainerLow: Color(0xFF151311),
  surfaceContainer: Color(0xFF1C1917),
  surfaceContainerHigh: Color(0xFF221F1C),
  surfaceContainerHighest: Color(0xFF292521),
  surfaceTint: Color(0xFFFFB95C),
  inverseSurface: Color(0xFFFEF8F5),
  onInverseSurface: Color(0xFF575452),
  inversePrimary: Color(0xFF855400),
  outline: Color(0xFF7A746F),
  outlineVariant: Color(0xFF4C4743),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
);

// The fixed roles hold still across brightnesses, so both schemes share them.
const _primaryFixed = Color(0xFFFFDDB7);
const _primaryFixedDim = Color(0xFFFFCB8D);
const _onPrimaryFixed = Color(0xFF5B3800);
const _onPrimaryFixedVariant = Color(0xFF815100);
const _secondaryFixed = Color(0xFFEBE1D9);
const _secondaryFixedDim = Color(0xFFDCD3CB);
const _onSecondaryFixed = Color(0xFF443E39);
const _onSecondaryFixedVariant = Color(0xFF615A54);
const _tertiaryFixed = Color(0xFFF7E8B7);
const _tertiaryFixedDim = Color(0xFFE8DAAA);
const _onTertiaryFixed = Color(0xFF4B421F);
const _onTertiaryFixedVariant = Color(0xFF695F38);

/// The app's theme for one of the two schemes.
///
/// The bar sits a step off the surface behind it, so the app's own edge is
/// distinct from what is being practised on: the same step the status bar
/// above it takes, since the bar paints behind that inset.
ThemeData keyRecallTheme(ColorScheme scheme) => ThemeData(
  colorScheme: scheme,
  appBarTheme: AppBarTheme(backgroundColor: scheme.surfaceContainerLow),
);

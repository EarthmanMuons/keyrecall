import 'package:keyrecall/features/input/input.dart';

/// Runs a test against the synthetic instrument, rather than the MIDI stack
/// there is no radio for.
final syntheticInstrument = inputSourceProvider.overrideWith(
  _SyntheticSource.new,
);

class _SyntheticSource extends InputSourceNotifier {
  @override
  InputSourceKind build() => InputSourceKind.demo;
}

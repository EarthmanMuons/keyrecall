/// MIDI transport for KeyRecall.
///
/// Three layers, each with one job:
///
/// 1. **Transport.** [MidiBleService] is a thin boundary around the plugin,
///    with hard timeouts on calls that can hang. No policy lives there.
/// 2. **Device graph.** [MidiDeviceManager] owns scanning, the device
///    snapshot, connect and disconnect, and reconciliation against what the
///    platform actually believes.
/// 3. **Connection workflow.** [MidiConnectionNotifier] owns the user-facing
///    state machine: auto-reconnect, backoff, cancellation, and the
///    single-flight guard that keeps two reconnect runs from overlapping.
///
/// What the rest of the app consumes is [midiTemporalEventsProvider], the
/// normalized stream defined by `keyrecall_input`. Everything above is how that
/// stream keeps working when an instrument is switched off, carried out of
/// range, or the app is backgrounded for an hour.
///
/// `midiNoteEventsProvider` is deliberately not exported. It reports note-on
/// and note-off as they arrive, so it does not read velocity-zero note-on as a
/// release, does not resolve repeats, and substitutes note 0 for a message
/// without one. Reading it as a performance would mistake a held chord for a
/// scale.
///
/// Vendored from WhatChord; see VENDORED.md for what that means for changes.
library;

export 'src/midi_debug.dart';
export 'src/models/bluetooth_access.dart';
export 'src/models/bluetooth_state.dart';
export 'src/models/bluetooth_unavailability.dart';
export 'src/models/midi_connection.dart';
export 'src/models/midi_constants.dart';
export 'src/models/midi_device.dart';
export 'src/models/midi_exception.dart';
export 'src/models/midi_message.dart';
export 'src/models/midi_note_state.dart';
export 'src/models/midi_preferences.dart';
export 'src/persistence/midi_preferences_keys.dart';
export 'src/providers/app_midi_lifecycle_provider.dart';
export 'src/providers/bluetooth_permission_service_provider.dart';
export 'src/providers/midi_ble_service_provider.dart';
export 'src/providers/midi_connection_notifier.dart';
export 'src/providers/midi_device_manager.dart';
export 'src/providers/midi_message_providers.dart';
export 'src/providers/midi_note_state_notifier.dart';
export 'src/providers/midi_output_sender_provider.dart';
export 'src/providers/midi_preferences_notifier.dart';
export 'src/providers/midi_temporal_events_provider.dart';
export 'src/providers/midi_wakelock_provider.dart';
export 'src/services/bluetooth_permission_service.dart';
export 'src/services/midi_ble_service.dart';
export 'src/services/midi_output_sender.dart';
export 'src/shared_preferences_provider.dart';

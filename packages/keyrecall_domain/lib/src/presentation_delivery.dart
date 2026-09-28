import 'package:meta/meta.dart';

/// Whether a channel gave the learner what the presentation resolved to give
/// them.
///
/// Distinct from the resolved condition. What an attempt was meant to contain
/// is a decision; what reached the learner is an outcome, and a device that
/// will not open an audio engine changes the second without changing the first.
enum ChannelDelivery {
  /// Everything the channel was asked for was supplied.
  complete('COMPLETE'),

  /// Some of it was supplied and the rest was not.
  partial('PARTIAL'),

  /// None of it was supplied.
  unavailable('UNAVAILABLE');

  const ChannelDelivery(this.id);

  /// Stable identifier, and the spelling the wire format takes.
  final String id;

  /// Whether the channel fell short of what it was asked for.
  bool get fellShort => this != ChannelDelivery.complete;
}

/// How much of the pulse the app managed to supply.
///
/// Audio preparation is best effort, so an attempt can proceed under a count-in
/// that never sounded or that started late and dropped the beats it missed.
/// Neither outcome changes what the attempt asked of the learner, and neither
/// may be recorded as a count-in that was supplied.
///
/// A delivered beat is one the audio layer accepted, not one anybody is known
/// to have heard. Nothing on this path reports back from the speaker, so that
/// is the strongest claim available: the app handed it over. Whether it reached
/// the room is a question only a device with playback completion could answer.
@immutable
class TempoDelivery {
  /// Beats asked for before the attempt begins.
  final int countInBeats;

  /// Beats asked for once the attempt has begun, which is a metronome.
  final int continuingBeats;

  /// Beats of [countInBeats] the audio layer accepted.
  final int deliveredCountInBeats;

  /// Beats of [continuingBeats] the audio layer accepted.
  ///
  /// What separates a pulse the learner held from one they were given: any
  /// beat here was supplied while the attempt was being observed.
  final int deliveredContinuingBeats;

  /// Why the pulse fell short, when the audio layer said.
  final String? failureReason;

  /// The only constructor that decides how much of the pulse was delivered, so
  /// no caller can record a shortfall as a complete count-in.
  TempoDelivery({
    required this.countInBeats,
    required this.continuingBeats,
    required this.deliveredCountInBeats,
    required this.deliveredContinuingBeats,
    this.failureReason,
  }) {
    _requireWithin(
      countInBeats,
      deliveredCountInBeats,
      'countInBeats',
      'deliveredCountInBeats',
    );
    _requireWithin(
      continuingBeats,
      deliveredContinuingBeats,
      'continuingBeats',
      'deliveredContinuingBeats',
    );
  }

  static void _requireWithin(
    int requested,
    int delivered,
    String requestedName,
    String deliveredName,
  ) {
    if (requested < 0) throw ArgumentError.value(requested, requestedName);
    if (delivered < 0 || delivered > requested) {
      throw ArgumentError.value(
        delivered,
        deliveredName,
        'must be within the $requested that were asked for',
      );
    }
  }

  /// A pulse nothing was asked of, which is what an attempt under
  /// `TempoSupport.none` owes the learner.
  TempoDelivery.notRequested() : this.complete(0);

  /// Every requested beat, handed over from the first.
  TempoDelivery.complete(int countInBeats, {int continuingBeats = 0})
    : this(
        countInBeats: countInBeats,
        continuingBeats: continuingBeats,
        deliveredCountInBeats: countInBeats,
        deliveredContinuingBeats: continuingBeats,
      );

  /// Nothing was handed over at all, for [reason].
  TempoDelivery.silent(
    int countInBeats, {
    int continuingBeats = 0,
    String? reason,
  }) : this(
         countInBeats: countInBeats,
         continuingBeats: continuingBeats,
         deliveredCountInBeats: 0,
         deliveredContinuingBeats: 0,
         failureReason: reason,
       );

  /// Beats the presentation asked the audio layer for.
  int get requestedBeats => countInBeats + continuingBeats;

  /// Beats of those the audio layer accepted.
  int get deliveredBeats => deliveredCountInBeats + deliveredContinuingBeats;

  /// Whether any beat was supplied after the count-in.
  bool get suppliedDuringAttempt => deliveredContinuingBeats > 0;

  /// How much of the requested pulse the audio layer took.
  ChannelDelivery get delivery {
    if (deliveredBeats == requestedBeats) return ChannelDelivery.complete;
    if (deliveredBeats == 0) return ChannelDelivery.unavailable;
    return ChannelDelivery.partial;
  }

  @override
  bool operator ==(Object other) =>
      other is TempoDelivery &&
      other.countInBeats == countInBeats &&
      other.continuingBeats == continuingBeats &&
      other.deliveredCountInBeats == deliveredCountInBeats &&
      other.deliveredContinuingBeats == deliveredContinuingBeats &&
      other.failureReason == failureReason;

  @override
  int get hashCode => Object.hash(
    countInBeats,
    continuingBeats,
    deliveredCountInBeats,
    deliveredContinuingBeats,
    failureReason,
  );

  @override
  String toString() =>
      'TempoDelivery(${delivery.id}, '
      'count-in $deliveredCountInBeats/$countInBeats, '
      'continuing $deliveredContinuingBeats/$continuingBeats)';
}

/// What the app managed to put in front of the learner, channel by channel.
///
/// Only the fallible channels are here. A cue the renderer is asked for either
/// draws or does not draw, and nothing between those is a state this app can
/// reach; audio is the channel that can half happen.
@immutable
class PresentationDelivery {
  /// What the pulse sounded.
  final TempoDelivery tempo;

  const PresentationDelivery({required this.tempo});

  /// Whether any channel gave the learner less than it was asked for.
  bool get fellShort => tempo.delivery.fellShort;

  /// Whether the learner was given a pulse while the attempt was observed.
  ///
  /// Asked of what was delivered rather than of what was requested, so a
  /// metronome that never sounded leaves the learner holding the pulse alone.
  bool get suppliedPulseDuringAttempt => tempo.suppliedDuringAttempt;

  @override
  bool operator ==(Object other) =>
      other is PresentationDelivery && other.tempo == tempo;

  @override
  int get hashCode => tempo.hashCode;

  @override
  String toString() => 'PresentationDelivery($tempo)';
}

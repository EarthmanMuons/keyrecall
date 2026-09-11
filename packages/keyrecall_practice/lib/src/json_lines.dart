import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:meta/meta.dart';

/// Where an append-only JSON-lines file stops being committed.
///
/// A record is committed when its terminating newline reached the disk. A
/// crash partway through an append leaves bytes after that newline, and those
/// bytes are not history: nothing acknowledged them, and the record they would
/// have formed was never returned to anyone.
@immutable
class CommittedLines {
  /// How many bytes the file holds.
  final int fileLength;

  /// Byte offset just past the last committed newline, zero when there is
  /// none.
  final int committedLength;

  /// The committed records, newline-separated, without a trailing newline.
  final String text;

  const CommittedLines({
    required this.fileLength,
    required this.committedLength,
    required this.text,
  });

  /// Whether the file holds no bytes at all.
  bool get isEmpty => fileLength == 0;

  /// Whether any record was ever committed.
  bool get hasCompleteRecord => committedLength > 0;

  /// Whether bytes follow the last committed record.
  bool get hasTornTail => committedLength != fileLength;
}

/// Reads the committed prefix of [file].
///
/// The boundary is found in the bytes, before anything is decoded. A torn tail
/// can end midway through a multi-byte character, and decoding first would
/// fail on a file that is entirely recoverable. Newline cannot appear inside a
/// UTF-8 sequence, so scanning bytes for it cannot land in the middle of a
/// character.
Future<CommittedLines> readCommittedLines(File file) async {
  final bytes = await file.readAsBytes();
  final committedLength = _committedLength(bytes);
  return CommittedLines(
    fileLength: bytes.length,
    committedLength: committedLength,
    text: committedLength == 0
        ? ''
        : _decode(
            Uint8List.sublistView(bytes, 0, committedLength - 1),
            file.path,
          ),
  );
}

/// Drops an incomplete final record so the next append writes after history.
///
/// Truncates at the byte offset of the last committed newline rather than
/// rewriting the valid prefix. Rewriting would remove committed records first
/// and put them back afterward, so a second interruption during recovery would
/// destroy history that the first one left intact.
Future<void> truncateTornTail(File file) async {
  if (!file.existsSync()) return;
  final bytes = await file.readAsBytes();
  final committedLength = _committedLength(bytes);
  if (committedLength == bytes.length) return;

  // Opened for append rather than for write, which would truncate to nothing
  // before this could choose where to cut.
  final handle = await file.open(mode: FileMode.writeOnlyAppend);
  try {
    await handle.truncate(committedLength);
    await handle.flush();
  } finally {
    await handle.close();
  }
}

int _committedLength(Uint8List bytes) {
  const newline = 0x0a;
  for (var i = bytes.length - 1; i >= 0; i--) {
    if (bytes[i] == newline) return i + 1;
  }
  return 0;
}

String _decode(Uint8List bytes, String path) {
  try {
    return utf8.decode(bytes);
  } on FormatException catch (error) {
    throw JournalFormatException(
      'committed records are not valid UTF-8: ${error.message}',
      location: path,
    );
  }
}

import 'dart:typed_data';

enum ProgressPhase { readHeader, deriveKey, decrypt, decode, done }

class ProgressEvent {
  final ProgressPhase phase;
  final double percent;
  final String label;
  final String? filename;
  final Uint8List? data;

  const ProgressEvent({
    required this.phase,
    required this.percent,
    required this.label,
    this.filename,
    this.data,
  });
}

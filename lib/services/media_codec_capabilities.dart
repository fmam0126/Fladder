import 'dart:developer';

import 'package:flutter/foundation.dart';

import 'package:fladder/src/media_codec_capabilities.g.dart' as pigeon;

/// Caches the video decoders reported by the device, so the device profile can be built synchronously.
class MediaCodecCapabilities {
  static final _api = pigeon.MediaCodecCapabilitiesPigeon();

  static List<pigeon.VideoDecoderCapability>? _videoDecoders;

  /// The decoders found on this device, or null when unknown (non-Android platforms or a failed query).
  static List<pigeon.VideoDecoderCapability>? get videoDecoders => _videoDecoders;

  static Future<void> load() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final decoders = await _api.getVideoDecoders();
      _videoDecoders = decoders.isEmpty ? null : decoders;
    } catch (e, st) {
      log('Failed to query video decoders: $e', error: e, stackTrace: st);
      _videoDecoders = null;
    }
  }
}

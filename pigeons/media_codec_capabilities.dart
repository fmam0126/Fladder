import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/media_codec_capabilities.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/app/src/main/kotlin/nl/jknaapen/fladder/api/MediaCodecCapabilities.g.kt',
    kotlinOptions: KotlinOptions(
      includeErrorClass: false,
    ),
    dartPackageName: 'nl_jknaapen_fladder.settings',
  ),
)
class VideoDecoderCapability {
  /// Jellyfin codec name (h264, hevc, av1, vp9, ...)
  final String codec;

  /// Whether at least one hardware accelerated decoder exists for this codec.
  final bool hardware;

  /// Largest width the best (hardware preferred) decoder can play at >= 30 fps.
  final int maxWidth;

  /// Largest height the best (hardware preferred) decoder can play at >= 30 fps.
  final int maxHeight;

  /// Whether the best (hardware preferred) decoder supports a 10-bit profile.
  final bool supports10Bit;

  const VideoDecoderCapability({
    required this.codec,
    required this.hardware,
    required this.maxWidth,
    required this.maxHeight,
    required this.supports10Bit,
  });
}

@HostApi()
abstract class MediaCodecCapabilitiesPigeon {
  List<VideoDecoderCapability> getVideoDecoders();
}

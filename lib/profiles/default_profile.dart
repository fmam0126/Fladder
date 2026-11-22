import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/models/settings/video_player_settings.dart';
import 'package:fladder/profiles/web_profile.dart';
import 'package:fladder/providers/video_player_provider.dart';
import 'package:fladder/services/media_codec_capabilities.dart';
import 'package:fladder/src/media_codec_capabilities.g.dart';

final videoProfileProvider = StateProvider.autoDispose<DeviceProfile>((ref) =>
    defaultProfile(ref.read(videoPlayerProvider.select((value) => value.backend)) ?? PlayerOptions.platformDefaults));

DeviceProfile defaultProfile(PlayerOptions player) {
  if (kIsWeb) return webProfile;
  final decoders = MediaCodecCapabilities.videoDecoders;
  if (decoders != null) return buildAndroidVideoProfile(decoders);
  return _permissiveProfile;
}

/// Codecs cheap enough to decode in software, so they direct play even without a hardware decoder.
const _lightCodecs = {'h264', 'vp8', 'mpeg4', 'mpeg2video', 'h263', 'vc1'};

/// Codecs that need a hardware decoder to direct play.
const _heavyCodecs = {'hevc', 'vp9', 'av1'};

const _transcodingProfiles = [
  TranscodingProfile(
    audioCodec: 'aac,mp3,mp2',
    container: 'ts',
    maxAudioChannels: '2',
    protocol: MediaStreamProtocol.hls,
    type: DlnaProfileType.video,
    videoCodec: 'h264',
  ),
];

const _subtitleProfiles = [
  SubtitleProfile(format: 'vtt', method: SubtitleDeliveryMethod.$external),
  SubtitleProfile(format: 'ass', method: SubtitleDeliveryMethod.$external),
  SubtitleProfile(format: 'ssa', method: SubtitleDeliveryMethod.$external),
  SubtitleProfile(format: 'pgssub', method: SubtitleDeliveryMethod.$external),
];

/// Used where the device decoders are unknown: lets the server direct play any video codec.
const _permissiveProfile = DeviceProfile(
  maxStreamingBitrate: 120000000,
  maxStaticBitrate: 120000000,
  musicStreamingTranscodingBitrate: 384000,
  directPlayProfiles: [
    DirectPlayProfile(
      type: DlnaProfileType.video,
    ),
    DirectPlayProfile(
      type: DlnaProfileType.audio,
    )
  ],
  transcodingProfiles: _transcodingProfiles,
  containerProfiles: [],
  subtitleProfiles: _subtitleProfiles,
);

/// Builds a profile from the decoders reported by the device.
///
/// Light codecs always direct play. Heavy codecs (hevc, vp9, av1) only direct play with a hardware decoder.
/// When a hardware decoder exists, its max resolution applies, and heavy codecs are limited to 8-bit
/// when the decoder has no 10-bit profile. Anything else is transcoded by the server.
DeviceProfile buildAndroidVideoProfile(List<VideoDecoderCapability> decoders) {
  final byCodec = {for (final decoder in decoders) decoder.codec: decoder};

  final directPlayCodecs = <String>[];
  final codecProfiles = <CodecProfile>[];

  for (final codec in [..._lightCodecs, ..._heavyCodecs]) {
    final decoder = byCodec[codec];
    final isHeavy = _heavyCodecs.contains(codec);

    if (decoder == null) {
      // No decoder reported. Light codecs are still decoded in software by mpv/ffmpeg.
      if (!isHeavy) directPlayCodecs.add(codec);
      continue;
    }

    if (isHeavy && !decoder.hardware) continue;
    directPlayCodecs.add(codec);

    if (!decoder.hardware) continue;

    final conditions = <ProfileCondition>[
      if (decoder.maxWidth > 0)
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.width,
          value: decoder.maxWidth.toString(),
          isRequired: false,
        ),
      if (decoder.maxHeight > 0)
        ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.height,
          value: decoder.maxHeight.toString(),
          isRequired: false,
        ),
      if (isHeavy && !decoder.supports10Bit)
        const ProfileCondition(
          condition: ProfileConditionType.lessthanequal,
          property: ProfileConditionValue.videobitdepth,
          value: '8',
          isRequired: false,
        ),
    ];

    if (conditions.isNotEmpty) {
      codecProfiles.add(CodecProfile(
        type: CodecType.video,
        codec: codec,
        conditions: conditions,
      ));
    }
  }

  return DeviceProfile(
    maxStreamingBitrate: _permissiveProfile.maxStreamingBitrate,
    maxStaticBitrate: _permissiveProfile.maxStaticBitrate,
    musicStreamingTranscodingBitrate: _permissiveProfile.musicStreamingTranscodingBitrate,
    directPlayProfiles: [
      DirectPlayProfile(
        type: DlnaProfileType.video,
        videoCodec: directPlayCodecs.join(','),
      ),
      const DirectPlayProfile(
        type: DlnaProfileType.audio,
      ),
    ],
    transcodingProfiles: _transcodingProfiles,
    containerProfiles: const [],
    codecProfiles: codecProfiles,
    subtitleProfiles: _subtitleProfiles,
  );
}

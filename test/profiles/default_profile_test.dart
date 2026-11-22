import 'package:flutter_test/flutter_test.dart';

import 'package:fladder/jellyfin/jellyfin_open_api.swagger.dart';
import 'package:fladder/profiles/default_profile.dart';
import 'package:fladder/src/media_codec_capabilities.g.dart';

VideoDecoderCapability _decoder(
  String codec, {
  required bool hardware,
  int maxWidth = 1920,
  int maxHeight = 1080,
  bool supports10Bit = false,
}) =>
    VideoDecoderCapability(
      codec: codec,
      hardware: hardware,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      supports10Bit: supports10Bit,
    );

/// Decoders reported by a Lenovo TB125FU (MediaTek mt6768): no AV1/VP9 hardware, HEVC Main (8-bit) only.
final _mt6768Decoders = [
  _decoder('h264', hardware: true),
  _decoder('hevc', hardware: true),
  _decoder('mpeg4', hardware: true),
  _decoder('h263', hardware: true, maxWidth: 1280, maxHeight: 720),
  _decoder('av1', hardware: false, supports10Bit: true),
  _decoder('vp9', hardware: false, supports10Bit: true),
  _decoder('vp8', hardware: false),
];

Set<String> _directPlayVideoCodecs(DeviceProfile profile) => profile.directPlayProfiles!
    .where((profile) => profile.type == DlnaProfileType.video)
    .expand((profile) => profile.videoCodec!.split(','))
    .toSet();

List<ProfileCondition> _conditionsFor(DeviceProfile profile, String codec) =>
    profile.codecProfiles!.where((profile) => profile.codec == codec).expand((profile) => profile.conditions!).toList();

void main() {
  group('buildAndroidVideoProfile', () {
    test('transcodes codecs without a hardware decoder and direct plays supported ones', () {
      final codecs = _directPlayVideoCodecs(buildAndroidVideoProfile(_mt6768Decoders));

      expect(codecs, containsAll(['h264', 'hevc', 'vp8', 'mpeg4']));
      expect(codecs, isNot(contains('av1')));
      expect(codecs, isNot(contains('vp9')));
    });

    test('limits hevc to the hardware decoder resolution and 8-bit', () {
      final conditions = _conditionsFor(buildAndroidVideoProfile(_mt6768Decoders), 'hevc');

      expect(
        conditions,
        contains(predicate<ProfileCondition>((c) =>
            c.property == ProfileConditionValue.width &&
            c.condition == ProfileConditionType.lessthanequal &&
            c.value == '1920')),
      );
      expect(
        conditions,
        contains(predicate<ProfileCondition>((c) =>
            c.property == ProfileConditionValue.videobitdepth &&
            c.condition == ProfileConditionType.lessthanequal &&
            c.value == '8')),
      );
    });

    test('direct plays av1 when a 10-bit 4K hardware decoder exists', () {
      final profile = buildAndroidVideoProfile([
        ..._mt6768Decoders.where((decoder) => decoder.codec != 'av1'),
        _decoder('av1', hardware: true, maxWidth: 3840, maxHeight: 2160, supports10Bit: true),
      ]);

      expect(_directPlayVideoCodecs(profile), contains('av1'));
      final conditions = _conditionsFor(profile, 'av1');
      expect(conditions.any((c) => c.property == ProfileConditionValue.videobitdepth), isFalse);
      expect(conditions.firstWhere((c) => c.property == ProfileConditionValue.width).value, '3840');
    });

    test('keeps light codecs that report no decoder at all', () {
      final codecs = _directPlayVideoCodecs(buildAndroidVideoProfile([_decoder('h264', hardware: true)]));

      expect(codecs, containsAll(['h264', 'vp8', 'mpeg2video']));
      expect(codecs, isNot(contains('hevc')));
    });
  });
}

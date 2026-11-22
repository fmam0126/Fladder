package nl.jknaapen.fladder.utility

import MediaCodecCapabilitiesPigeon
import VideoDecoderCapability
import android.media.MediaCodecInfo
import android.media.MediaCodecInfo.CodecProfileLevel
import android.media.MediaCodecList
import android.os.Build
import android.util.Log

/**
 * Reports which video codecs this device can decode, whether a hardware decoder exists for them,
 * and the limits of the best decoder. Used to build the Jellyfin device profile so the server only
 * direct plays streams the device can actually handle.
 */
object MediaCodecCapabilities : MediaCodecCapabilitiesPigeon {
    private const val TAG = "MediaCodecCapabilities"

    private val mimeToCodec = mapOf(
        "video/avc" to "h264",
        "video/hevc" to "hevc",
        "video/av01" to "av1",
        "video/x-vnd.on2.vp9" to "vp9",
        "video/x-vnd.on2.vp8" to "vp8",
        "video/mp4v-es" to "mpeg4",
        "video/mpeg2" to "mpeg2video",
        "video/3gpp" to "h263",
        "video/wvc1" to "vc1",
    )

    private val tenBitProfiles = mapOf(
        "video/avc" to setOf(CodecProfileLevel.AVCProfileHigh10),
        "video/hevc" to setOf(
            CodecProfileLevel.HEVCProfileMain10,
            CodecProfileLevel.HEVCProfileMain10HDR10,
            CodecProfileLevel.HEVCProfileMain10HDR10Plus,
        ),
        "video/x-vnd.on2.vp9" to setOf(
            CodecProfileLevel.VP9Profile2,
            CodecProfileLevel.VP9Profile3,
            CodecProfileLevel.VP9Profile2HDR,
            CodecProfileLevel.VP9Profile3HDR,
            CodecProfileLevel.VP9Profile2HDR10Plus,
            CodecProfileLevel.VP9Profile3HDR10Plus,
        ),
        "video/av01" to setOf(
            CodecProfileLevel.AV1ProfileMain10,
            CodecProfileLevel.AV1ProfileMain10HDR10,
            CodecProfileLevel.AV1ProfileMain10HDR10Plus,
        ),
    )

    /** Candidate resolutions, largest first. */
    private val candidateSizes = listOf(
        3840 to 2160,
        2560 to 1440,
        1920 to 1080,
        1280 to 720,
    )

    private const val MIN_FRAME_RATE = 30.0

    private data class DecoderInfo(
        val hardware: Boolean,
        val maxWidth: Int,
        val maxHeight: Int,
        val supports10Bit: Boolean,
    )

    private var cached: List<VideoDecoderCapability>? = null

    override fun getVideoDecoders(): List<VideoDecoderCapability> {
        cached?.let { return it }

        val decoders = mutableMapOf<String, MutableList<DecoderInfo>>()
        for (info in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
            if (info.isEncoder) continue
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && info.isAlias) continue
            for (mime in info.supportedTypes) {
                val type = mime.lowercase()
                val codec = mimeToCodec[type] ?: continue
                try {
                    decoders.getOrPut(codec) { mutableListOf() }.add(describe(info, type))
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to read capabilities of ${info.name} for $type", e)
                }
            }
        }

        val result = decoders.map { (codec, infos) ->
            val hardwareDecoders = infos.filter { it.hardware }
            val best = hardwareDecoders.ifEmpty { infos }
            val largest = best.maxBy { it.maxWidth.toLong() * it.maxHeight }
            VideoDecoderCapability(
                codec = codec,
                hardware = hardwareDecoders.isNotEmpty(),
                maxWidth = largest.maxWidth.toLong(),
                maxHeight = largest.maxHeight.toLong(),
                supports10Bit = best.any { it.supports10Bit },
            )
        }
        result.forEach { Log.i(TAG, it.toString()) }
        cached = result
        return result
    }

    private fun describe(info: MediaCodecInfo, mime: String): DecoderInfo {
        val caps = info.getCapabilitiesForType(mime)
        val video = caps.videoCapabilities
        val (width, height) = video?.let { maxPlayableSize(it) } ?: (0 to 0)
        val tenBit = tenBitProfiles[mime]
        return DecoderInfo(
            hardware = isHardware(info),
            maxWidth = width,
            maxHeight = height,
            supports10Bit = tenBit != null && caps.profileLevels.any { it.profile in tenBit },
        )
    }

    private fun isHardware(info: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return info.isHardwareAccelerated
        }
        val name = info.name.lowercase()
        return !(name.startsWith("omx.google.") || name.startsWith("c2.android.") || name.contains(".sw."))
    }

    /** Largest candidate size the decoder can play at [MIN_FRAME_RATE], in either orientation. */
    private fun maxPlayableSize(video: MediaCodecInfo.VideoCapabilities): Pair<Int, Int> {
        for ((w, h) in candidateSizes) {
            if (canPlay(video, w, h) || canPlay(video, h, w)) return w to h
        }
        return video.supportedWidths.upper to video.supportedHeights.upper
    }

    private fun canPlay(video: MediaCodecInfo.VideoCapabilities, width: Int, height: Int): Boolean {
        if (!video.isSizeSupported(width, height)) return false
        val measured = try {
            video.getAchievableFrameRatesFor(width, height)
        } catch (_: IllegalArgumentException) {
            null
        }
        return if (measured != null) {
            measured.upper >= MIN_FRAME_RATE
        } else {
            video.areSizeAndRateSupported(width, height, MIN_FRAME_RATE)
        }
    }
}

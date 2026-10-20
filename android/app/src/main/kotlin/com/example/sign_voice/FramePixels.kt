package com.example.sign_voice

/** Handles padded YUV planes and interleaved chroma without assuming NV21. */
internal object FramePixels {
    fun argb(width: Int, height: Int, format: String, planes: List<Map<String, Any?>>,
             rotation: Int = 0, reuse: IntArray? = null): IntArray {
            require(rotation in listOf(0,90,180,270))
            val rgba = reuse?.takeIf { it.size == width * height } ?: IntArray(width * height)
            if (format == "yuv420") {
                require(planes.size == 3)
                val ys = planes[0]["bytes"] as ByteArray; val us = planes[1]["bytes"] as ByteArray; val vs = planes[2]["bytes"] as ByteArray
                val yr = (planes[0]["row_stride"] as Number).toInt(); val yp = (planes[0]["pixel_stride"] as Number).toInt()
                val ur = (planes[1]["row_stride"] as Number).toInt(); val up = (planes[1]["pixel_stride"] as Number).toInt()
                val vr = (planes[2]["row_stride"] as Number).toInt(); val vp = (planes[2]["pixel_stride"] as Number).toInt()
                for (y in 0 until height) for (x in 0 until width) {
                    val yy = ((ys[y*yr+x*yp].toInt() and 255)-16).coerceAtLeast(0)
                    val u = (us[(y/2)*ur+(x/2)*up].toInt() and 255)-128
                    val v = (vs[(y/2)*vr+(x/2)*vp].toInt() and 255)-128
                    val r = ((298*yy+409*v+128) shr 8).coerceIn(0,255)
                    val g = ((298*yy-100*u-208*v+128) shr 8).coerceIn(0,255)
                    val b = ((298*yy+516*u+128) shr 8).coerceIn(0,255)
                    rgba[index(x,y,width,height,rotation)] = (255 shl 24) or (r shl 16) or (g shl 8) or b
                }
            } else {
                require(format == "bgra8888" && planes.size == 1)
                val bytes = planes[0]["bytes"] as ByteArray; val stride = (planes[0]["row_stride"] as Number).toInt()
                for (y in 0 until height) for (x in 0 until width) {
                    val i=y*stride+x*4
                    rgba[index(x,y,width,height,rotation)]=(255 shl 24) or ((bytes[i+2].toInt() and 255) shl 16) or
                        ((bytes[i+1].toInt() and 255) shl 8) or (bytes[i].toInt() and 255)
                }
            }
        return rgba
    }
    private fun index(x: Int, y: Int, width: Int, height: Int, rotation: Int): Int = when(rotation) {
        90 -> x * height + height - 1 - y
        180 -> (height - 1 - y) * width + width - 1 - x
        270 -> (width - 1 - x) * height + y
        else -> y * width + x
    }
}

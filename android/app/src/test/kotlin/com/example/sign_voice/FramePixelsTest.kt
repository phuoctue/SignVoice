package com.example.sign_voice

import org.junit.Assert.*
import org.junit.Test

class FramePixelsTest {
    private fun plane(bytes: ByteArray, row: Int, pixel: Int) = mapOf<String, Any?>(
        "bytes" to bytes, "row_stride" to row, "pixel_stride" to pixel)
    @Test fun paddedYuvRowsAndInterleavedChroma() {
        val y = byteArrayOf(16,235.toByte(),99,99,81,145.toByte(),99,99)
        val u = byteArrayOf(128.toByte(),77,77)
        val v = byteArrayOf(128.toByte(),66,66)
        val rgba = FramePixels.argb(2,2,"yuv420",listOf(plane(y,4,1),plane(u,3,2),plane(v,3,2)))
        assertEquals(0xff000000.toInt(),rgba[0]); assertEquals(0xffffffff.toInt(),rgba[1])
        assertEquals(rgba[2] and 255,(rgba[2] shr 8) and 255)
        assertTrue((rgba[2] and 255) < (rgba[3] and 255))
    }
    @Test fun chromaPixelStrideTwoUsesTheRightSample() {
        val y=ByteArray(8){81}; val u=byteArrayOf(90,0,128.toByte(),0)
        val v=byteArrayOf(240.toByte(),0,128.toByte(),0)
        val rgba=FramePixels.argb(4,2,"yuv420",listOf(plane(y,4,1),plane(u,4,2),plane(v,4,2)))
        assertTrue(((rgba[0] shr 16) and 255) > 240)
        assertEquals(rgba[2] and 255,(rgba[2] shr 16) and 255)
        assertEquals(rgba[0],rgba[4]); assertEquals(rgba[2],rgba[6])
    }
    @Test fun paddedBgraIsNotMirroredOrSwapped() {
        val bytes=byteArrayOf(3,2,1,0,6,5,4,0,99,99,99,99,9,8,7,0,12,11,10,0)
        val rgba=FramePixels.argb(2,2,"bgra8888",listOf(plane(bytes,12,4)))
        assertArrayEquals(intArrayOf(0xff010203.toInt(),0xff040506.toInt(),0xff070809.toInt(),0xff0a0b0c.toInt()),rgba)
    }
    @Test fun fusedRotationPreservesNonSquareFrameAndFrontIsNotMirrored() {
        val bytes=ByteArray(24)
        for (i in 0 until 6) bytes[i*4+2]=(i+1).toByte()
        val planes=listOf(plane(bytes,8,4))
        val expected=mapOf(0 to intArrayOf(1,2,3,4,5,6),90 to intArrayOf(5,3,1,6,4,2),
            180 to intArrayOf(6,5,4,3,2,1),270 to intArrayOf(2,4,6,1,3,5))
        for ((rotation,order) in expected) {
            val actual=FramePixels.argb(2,3,"bgra8888",planes,rotation)
            assertArrayEquals("rotation $rotation",order,actual.map { (it shr 16) and 255 }.toIntArray())
        }
    }
    @Test fun rotatedYuvReusesScratchWithoutChangingColors() {
        val planes=listOf(plane(byteArrayOf(16,235.toByte(),81,145.toByte()),2,1),
            plane(byteArrayOf(128.toByte()),1,1),plane(byteArrayOf(128.toByte()),1,1))
        val original=FramePixels.argb(2,2,"yuv420",planes)
        val scratch=IntArray(4)
        val rotated=FramePixels.argb(2,2,"yuv420",planes,90,scratch)
        assertSame(scratch,rotated)
        assertArrayEquals(intArrayOf(original[2],original[0],original[3],original[1]),rotated)
        assertNotSame(scratch,FramePixels.argb(2,2,"yuv420",planes,0,IntArray(1)))
    }
}

import Accelerate
import AVFoundation
import CoreVideo

struct FrameProcessor {

    /// Target size for motion analysis (downscaled for performance)
    static let analysisSize = CGSize(width: 160, height: 120)

    /// Convert BGRA pixel buffer to grayscale with downscaling
    /// Uses a simplified but efficient approach
    static func toGrayscale(pixelBuffer: CVPixelBuffer, targetSize: CGSize = analysisSize) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let targetWidth = Int(targetSize.width)
        let targetHeight = Int(targetSize.height)
        let targetPixelCount = targetWidth * targetHeight

        var result = [UInt8](repeating: 0, count: targetPixelCount)

        // Scale factors for downsampling
        let xScale = Float(width) / Float(targetWidth)
        let yScale = Float(height) / Float(targetHeight)

        // Luminance coefficients (ITU-R BT.601)
        let rCoeff: Float = 0.299
        let gCoeff: Float = 0.587
        let bCoeff: Float = 0.114

        let pixels = baseAddress.assumingMemoryBound(to: UInt8.self)

        for y in 0..<targetHeight {
            let srcY = Int(Float(y) * yScale)
            for x in 0..<targetWidth {
                let srcX = Int(Float(x) * xScale)

                // BGRA format: B at offset 0, G at 1, R at 2, A at 3
                let pixelOffset = srcY * bytesPerRow + srcX * 4
                let b = Float(pixels[pixelOffset])
                let g = Float(pixels[pixelOffset + 1])
                let r = Float(pixels[pixelOffset + 2])

                // Calculate luminance
                let luminance = r * rCoeff + g * gCoeff + b * bCoeff
                result[y * targetWidth + x] = UInt8(min(255, max(0, luminance)))
            }
        }

        return result
    }

    /// Calculate absolute difference between two grayscale buffers
    /// Returns a buffer where each pixel is |current - previous|
    static func absoluteDifference(current: [UInt8], previous: [UInt8]) -> [UInt8]? {
        guard current.count == previous.count else {
            return nil
        }

        let count = current.count
        var result = [UInt8](repeating: 0, count: count)

        // Convert to Float for vDSP operations
        var currentFloat = [Float](repeating: 0, count: count)
        var previousFloat = [Float](repeating: 0, count: count)
        var diffFloat = [Float](repeating: 0, count: count)

        // Convert UInt8 to Float
        vDSP_vfltu8(current, 1, &currentFloat, 1, vDSP_Length(count))
        vDSP_vfltu8(previous, 1, &previousFloat, 1, vDSP_Length(count))

        // Subtract: diff = current - previous
        vDSP_vsub(previousFloat, 1, currentFloat, 1, &diffFloat, 1, vDSP_Length(count))

        // Take absolute value
        vDSP_vabs(diffFloat, 1, &diffFloat, 1, vDSP_Length(count))

        // Convert back to UInt8
        vDSP_vfixu8(diffFloat, 1, &result, 1, vDSP_Length(count))

        return result
    }

    /// Count pixels above threshold and return percentage (0.0 - 1.0)
    /// threshold: pixel difference value to consider as "changed" (0-255)
    static func motionPercentage(diffBuffer: [UInt8], threshold: UInt8) -> Float {
        guard !diffBuffer.isEmpty else { return 0.0 }

        var changedCount = 0
        let thresholdInt = Int(threshold)

        // Count pixels above threshold
        for pixel in diffBuffer {
            if Int(pixel) > thresholdInt {
                changedCount += 1
            }
        }

        return Float(changedCount) / Float(diffBuffer.count)
    }

    /// Optimized version using Accelerate
    static func motionPercentageOptimized(diffBuffer: [UInt8], threshold: UInt8) -> Float {
        guard !diffBuffer.isEmpty else { return 0.0 }

        let count = diffBuffer.count

        // Convert to float for comparison
        var floatBuffer = [Float](repeating: 0, count: count)
        vDSP_vfltu8(diffBuffer, 1, &floatBuffer, 1, vDSP_Length(count))

        // Count values above threshold
        let thresholdFloat = Float(threshold)
        var changedCount: Float = 0

        for value in floatBuffer {
            if value > thresholdFloat {
                changedCount += 1
            }
        }

        return changedCount / Float(count)
    }
}

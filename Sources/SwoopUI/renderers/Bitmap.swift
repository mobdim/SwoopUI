import Foundation
import Flynn

// swiftlint:disable identifier_name
// swiftlint:disable cyclomatic_complexity
// swiftlint:disable function_parameter_count
// swiftlint:disable function_body_length
// swiftlint:disable type_body_length

// We work in RGBA 32-bit color values. This means we need to worry about endianness
// On big endian, that's R-G-B-A
// On little endian, that's A-B-G-R

typealias PixelFunc = ((UInt32, UInt32) -> UInt32)

@inline(__always)
public func pixelCopy(_ dst: UInt32, _ src: UInt32) -> UInt32 {
    return src
}

@inline(__always)
public func pixelSrcOver(_ dst: UInt32, _ src: UInt32) -> UInt32 {
    let aSrc = ((src >> BYTE_ALPHA) & 0xFF)
    let aDst = ((dst >> BYTE_ALPHA) & 0xFF)
    let r = (((dst >> BYTE_RED) & 0xFF) * (255 - aSrc) + ((src >> BYTE_RED) & 0xFF) * aSrc) >> 8
    let g = (((dst >> BYTE_GREEN) & 0xFF) * (255 - aSrc) + ((src >> BYTE_GREEN) & 0xFF) * aSrc) >> 8
    let b = (((dst >> BYTE_BLUE) & 0xFF) * (255 - aSrc) + ((src >> BYTE_BLUE) & 0xFF) * aSrc) >> 8
    return (r << BYTE_RED) | (g << BYTE_GREEN) | (b << BYTE_BLUE) | (((aSrc + aDst) & 0xFF ) << BYTE_ALPHA)
}

public class Bitmap {
    private static var debugWarning = false
    private static var zeroBytes = UnsafeMutablePointer<UInt32>.allocate(capacity: 0)

    private static func checkDebugWarning() {
        #if DEBUG
        if debugWarning == false {
            debugWarning = true
            print("warning: using Bitmap in debug mode will be extremely slow")
        }
        #endif
    }

    public struct BitmapInfo {
        public let width: Int
        public let height: Int
        public let channels: Int
        public let bytesPerRow: Int
        public let bytes32: UnsafeMutablePointer<UInt32>
    }

    private var allocated: Int = 0

    private var width: Int = 0
    private var height: Int = 0
    private let channels: Int = 4

    private var bytes32: UnsafeMutablePointer<UInt32>

    public var bytesPerRow: Int {
        return width * channels
    }

    public var info: BitmapInfo {
        return BitmapInfo(width: width, height: height, channels: channels, bytesPerRow: bytesPerRow, bytes32: bytes32)
    }

    init(_ width: Int, _ height: Int) {
        Bitmap.checkDebugWarning()

        self.width = width
        self.height = height

        allocated = width * height * channels
        bytes32 = UnsafeMutablePointer<UInt32>.allocate(capacity: width * height)

        clear()
    }

    deinit {
        deallocate(bytes32)
    }

    private func deallocate(_ bytePtr: UnsafeMutablePointer<UInt32>) {
        if bytePtr != Bitmap.zeroBytes {
            bytePtr.deallocate()
        }
    }

    func resize(_ width: Int, _ height: Int) {
        if self.width != width || self.height != height {
            self.width = width
            self.height = height

            let newAllocatedSize = width * height * channels
            if newAllocatedSize <= allocated {
                return
            }

            deallocate(bytes32)
            allocated = newAllocatedSize
            bytes32 = UnsafeMutablePointer<UInt32>.allocate(capacity: width * height)
        }
    }

    func scaleTo(_ width: Int, _ height: Int) {
        if self.width != width || self.height != height {
            let old = self.info
            bytes32 = Bitmap.zeroBytes

            resize(width, height)

            copyAndDeallocateFromOldBitmap(old)
        }
    }

    func recoverMemory() {
        if allocated > width * height * channels {
            let old = self.info
            bytes32 = Bitmap.zeroBytes

            allocated = width * height * channels
            bytes32 = UnsafeMutablePointer<UInt32>.allocate(capacity: width * height)

            copyAndDeallocateFromOldBitmap(old)
        }
    }

    private func copyAndDeallocateFromOldBitmap(_ old: BitmapInfo) {
        blit(bytes32,
             Rect(x: 0, y: 0, width: width, height: height),
             bytesPerRow,
             old.bytes32,
             Rect(x: 0, y: 0, width: old.width, height: old.height),
             old.bytesPerRow,
             pixelCopy)

        deallocate(old.bytes32)
    }

    func clear() {
        bytes32.initialize(repeating: 0, count: width * height)
    }

    func raw() -> Data {
        return Data(bytesNoCopy: bytes32, count: width * height * channels, deallocator: .none)
    }

    func rawRGBA() -> Data {
        var data = Data(bytes: bytes32, count: width * height * channels)
        data.withUnsafeMutableBytes({ (bytes: UnsafeMutablePointer<UInt32>) -> Void in
            var ptr = bytes
            for _ in 0..<(width*height) {
                ptr.pointee = ptr.pointee.bigEndian
                ptr += 1
            }
        })
        return data
    }

    func ascii() -> String {
        // Convert each pixel to greyscale value 0-9, then print each pixel as single ascii digit
        var ptr = bytes32
        var string = String()

        for y in 0..<height {

            if y == 0 {
                string.append("+")
                for _ in 0..<width {
                    string.append("-")
                }
                string.append("+\n")
            }

            string.append("|")

            for _ in 0..<width {
                let color = ptr.pointee
                let red = Float( (color >> BYTE_RED) & 0xFF ) / 255.0
                let green = Float( (color >> BYTE_GREEN) & 0xFF ) / 255.0
                let blue = Float( (color >> BYTE_BLUE) & 0xFF ) / 255.0

                let v = Int((red * 0.299 + green * 0.587 + blue * 0.114) * 10.0)
                switch v {
                case 0: string.append("@")
                case 1: string.append("%")
                case 2: string.append("#")
                case 3: string.append("*")
                case 4: string.append("+")
                case 5: string.append("=")
                case 6: string.append("-")
                case 7: string.append(":")
                case 8: string.append(".")
                default: string.append(" ")
                }
                ptr += 1
            }
            string.append("|")
            string.append("\n")

            if y == height-1 {
                string.append("+")
                for _ in 0..<width {
                    string.append("-")
                }
                string.append("+\n")
            }
        }
        return string
    }

    // MARK: - Public Drawing

    func get(_ x: Int, _ y: Int) -> UInt32 {
        return bytes32[y * width + x]
    }

    func set(_ x: Int, _ y: Int, _ color: Color) {
        bytes32[y * width + x] = color.rgba32
    }

    // MARK: - Fill

    func fill(_ color: Color) {
        bytes32.initialize(repeating: color.rgba32, count: width * height)
    }

    func fill(_ color: Color, _ dstRect: Rect, _ function: PixelFunc = pixelSrcOver) {
        if ((color.rgba32 >> BYTE_ALPHA) & 0xFF) == 255 {
            blitColor(bytes32,
                      dstRect,
                      bytesPerRow,
                      color.rgba32,
                      pixelCopy)
        } else {
            blitColor(bytes32,
                      dstRect,
                      bytesPerRow,
                      color.rgba32,
                      function)
        }
    }

    // MARK: - Draw

    func draw(_ srcBitmap: Bitmap, _ srcRect: Rect, _ dstRect: Rect, _ function: PixelFunc = pixelSrcOver) {
        if srcRect.width == dstRect.width && srcRect.height == dstRect.height {
            blitExact(bytes32,
                      dstRect,
                      bytesPerRow,
                      srcBitmap.bytes32,
                      srcRect,
                      srcBitmap.bytesPerRow,
                      function)
            return
        }

        blit(bytes32,
             dstRect,
             bytesPerRow,
             srcBitmap.bytes32,
             srcRect,
             srcBitmap.bytesPerRow,
             function)
    }

    func draw(_ srcBitmap: Bitmap, _ dstRect: Rect, _ function: PixelFunc = pixelSrcOver) {
        draw(srcBitmap,
             Rect(x: 0, y: 0, width: srcBitmap.width, height: srcBitmap.height),
             dstRect,
             function)
    }

    func draw(_ srcBitmap: Bitmap, _ dstPoint: Point, _ function: PixelFunc = pixelSrcOver) {
        draw(srcBitmap,
             Rect(x: dstPoint.x, y: dstPoint.y, width: srcBitmap.width, height: srcBitmap.height),
             function)
    }

    func draw(_ srcBitmap: Bitmap, _ function: PixelFunc = pixelSrcOver) {
        draw(srcBitmap,
             Rect(x: 0, y: 0, width: srcBitmap.width, height: srcBitmap.height),
             Rect(x: 0, y: 0, width: srcBitmap.width, height: srcBitmap.height),
             function)
    }

    // MARK: - Private Drawing

    private func blitColor(_ dstPtr32: UnsafeMutablePointer<UInt32>,
                           _ dstRect: Rect,
                           _ dstRowBytes: Int,
                           _ color: UInt32,
                           _ function: PixelFunc) {
        // Assumes that the two rectangles are the same size and
        // do not exceed the bounds of their respective bitmaps
        let dstRowOffset = (dstRowBytes / 4)
        var dst = dstPtr32 + (dstRect.y * dstRowOffset) + dstRect.x
        let dstDelta = dstRowOffset - dstRect.width
        for _ in 0..<dstRect.height {
            for _ in 0..<dstRect.width {
                dst.pointee = function(dst.pointee, color)
                dst += 1
            }
            dst += dstDelta
        }
    }

    private func blitExact(_ dstPtr32: UnsafeMutablePointer<UInt32>,
                           _ dstRect: Rect,
                           _ dstRowBytes: Int,
                           _ srcPtr32: UnsafeMutablePointer<UInt32>,
                           _ srcRect: Rect,
                           _ srcRowBytes: Int,
                           _ function: PixelFunc) {
        // Assumes that the two rectangles are the same size and
        // do not exceed the bounds of their respective bitmaps
        let dstRowOffset = (dstRowBytes / 4)
        let srcRowOffset = (srcRowBytes / 4)
        var dst = dstPtr32 + (dstRect.y * dstRowOffset) + dstRect.x
        var src = srcPtr32 + (srcRect.y * srcRowOffset) + srcRect.x
        let dstDelta = dstRowOffset - dstRect.width
        let srcDelta = srcRowOffset - srcRect.width
        for _ in 0..<dstRect.height {
            for _ in 0..<dstRect.width {
                dst.pointee = function(dst.pointee, src.pointee)
                dst += 1
                src += 1
            }
            dst += dstDelta
            src += srcDelta
        }
    }

    private func blit(_ dstPtr32: UnsafeMutablePointer<UInt32>,
                      _ dstRect: Rect,
                      _ dstRowBytes: Int,
                      _ srcPtr32: UnsafeMutablePointer<UInt32>,
                      _ srcRect: Rect,
                      _ srcRowBytes: Int,
                      _ function: PixelFunc ) {
        // Assumes that the rectangles do not exceed the
        // bounds of their respective bitmaps
        // adapted from: fastBitmap.c in Graphics Gems 2
        let dstRowOffset = (dstRowBytes / 4)
        let srcRowOffset = (srcRowBytes / 4)

        let xs1 = srcRect.x
        var ys1 = srcRect.y
        let xs2 = srcRect.x + srcRect.width - 1
        let ys2 = srcRect.y + srcRect.height - 1

        let xd1 = dstRect.x
        var yd1 = dstRect.y
        let xd2 = dstRect.x + dstRect.width - 1
        let yd2 = dstRect.y + dstRect.height - 1

        let dx = abs(yd2 - yd1)
        var dy = abs(ys2 - ys1)
        let sx = (yd2 - yd1) > 0 ? 1 : -1
        let sy = (ys2 - ys1) > 0 ? 1 : -1
        var e = (dy << 1) - dx
        let dx2 = dx != 0 ? dx << 1 : 1

        var dstPtr = dstPtr32
        var srcPtr = srcPtr32

        dy = dy << 1

        for _ in 0...dx {

            if true {
                let dx = abs(xd2 - xd1)
                var dy = abs(xs2 - xs1)
                let sx = (xd2 - xd1) > 0 ? 1 : -1
                let sy = (xs2 - xs1) > 0 ? 1 : -1
                var e = (dy << 1) - dx
                let dx2 = dx != 0 ? dx << 1 : 1

                dy = dy << 1

                dstPtr = dstPtr32 + yd1 * dstRowOffset + xd1
                srcPtr = srcPtr32 + ys1 * srcRowOffset + xs1

                for _ in 0...dx {
                    dstPtr.pointee = function(dstPtr.pointee, srcPtr.pointee)

                    while e >= 0 {
                        srcPtr += sy
                        e -= dx2
                    }
                    dstPtr += sx
                    e += dy
                }
            }

            while e >= 0 {
                ys1 += sy
                e -= dx2
            }
            yd1 += sx
            e += dy
        }
    }
}

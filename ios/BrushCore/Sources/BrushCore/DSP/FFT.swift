import Foundation

/// Iterative radix-2 complex FFT. Pure Swift, so the same code runs on iOS,
/// watchOS and macOS (`swift test`). Sizes used by the app: 1024 and 8192.
public final class FFT {
    public let n: Int
    private let cosTable: [Double]
    private let sinTable: [Double]
    private let bitReverse: [Int]

    public init(n: Int) {
        precondition(n > 1 && (n & (n - 1)) == 0, "FFT size must be a power of two")
        self.n = n
        var levels = 0
        var m = n
        while m > 1 { m >>= 1; levels += 1 }
        var c = [Double](repeating: 0, count: n / 2)
        var s = [Double](repeating: 0, count: n / 2)
        for k in 0..<(n / 2) {
            let a = 2.0 * Double.pi * Double(k) / Double(n)
            c[k] = cos(a)
            s[k] = sin(a)
        }
        cosTable = c
        sinTable = s
        var rev = [Int](repeating: 0, count: n)
        for i in 0..<n {
            var x = i
            var r = 0
            for _ in 0..<levels {
                r = (r << 1) | (x & 1)
                x >>= 1
            }
            rev[i] = r
        }
        bitReverse = rev
    }

    /// In-place forward DFT: X[k] = sum x[j] * exp(-2*pi*i*j*k/n).
    public func transform(re: inout [Double], im: inout [Double]) {
        for i in 0..<n {
            let j = bitReverse[i]
            if j > i {
                re.swapAt(i, j)
                im.swapAt(i, j)
            }
        }
        var size = 2
        while size <= n {
            let half = size / 2
            let step = n / size
            var start = 0
            while start < n {
                var k = 0
                for j in start..<(start + half) {
                    let c = cosTable[k]
                    let s = sinTable[k]
                    let l = j + half
                    let tre = re[l] * c + im[l] * s
                    let tim = im[l] * c - re[l] * s
                    re[l] = re[j] - tre
                    im[l] = im[j] - tim
                    re[j] += tre
                    im[j] += tim
                    k += step
                }
                start += size
            }
            size *= 2
        }
    }

    /// |X[k]|^2 for k = 0...n/2 of a real signal (zero-padded or truncated to n).
    public func powerSpectrum(_ x: [Double]) -> [Double] {
        var re = [Double](repeating: 0, count: n)
        var im = [Double](repeating: 0, count: n)
        let m = Swift.min(x.count, n)
        for i in 0..<m { re[i] = x[i] }
        transform(re: &re, im: &im)
        var out = [Double](repeating: 0, count: n / 2 + 1)
        for k in 0...(n / 2) {
            out[k] = re[k] * re[k] + im[k] * im[k]
        }
        return out
    }
}

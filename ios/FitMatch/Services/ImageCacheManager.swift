import SwiftUI
import Combine
import ImageIO
import CryptoKit

// MARK: - Production-Grade Ultra-Fast Two-Tier Image Cache (Memory + Disk + Off-Thread Decoding)

public final class ImageCacheManager {
    public static let shared = ImageCacheManager()

    // L1: In-Memory Fast Cache
    private let memoryCache = NSCache<NSString, UIImage>()

    // L2: Persistent Disk Cache Directory
    private let diskCacheURL: URL

    // Request De-duplication & Synchronization
    private let lock = NSLock()
    private var inFlightTasks: [String: Task<UIImage?, Never>] = [:]

    // Custom Dedicated URLSession for Images with HTTP/2 and Aggressive Keep-Alive
    private let session: URLSession

    private init() {
        // Configure Memory Cache Limits (160 MB, up to 600 images)
        memoryCache.totalCostLimit = 160 * 1024 * 1024
        memoryCache.countLimit = 600

        // Configure Disk Cache Path
        let fileManager = FileManager.default
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = cachesDirectory.appendingPathComponent("FitMatchImageCache", isDirectory: true)

        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true, attributes: nil)

        // Optimized URLSession configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)

        // Evict memory on OS low memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clearMemoryCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc public func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    // MARK: - Fast Synchronous L1 Lookup (0ms overhead)

    public func cachedImage(for url: URL?, maxPixelSize: CGFloat = 800) -> UIImage? {
        guard let url = url else { return nil }
        let baseKey = cacheKey(for: url)
        if maxPixelSize > 1200,
           let hiRes = memoryCache.object(forKey: "\(baseKey)_hi" as NSString) {
            return hiRes
        }
        return memoryCache.object(forKey: baseKey as NSString)
    }

    // MARK: - Asynchronous Load (Memory -> Disk -> Network with Background Decompression)

    public func loadImage(for url: URL?, maxPixelSize: CGFloat = 800) async -> UIImage? {
        guard let url = url else { return nil }
        let baseKey = cacheKey(for: url)
        let memKey = maxPixelSize > 1200 ? "\(baseKey)_hi" : baseKey
        let keyNs = memKey as NSString

        // 1. Check L1 Memory Cache
        if let memoryHit = memoryCache.object(forKey: keyNs) {
            return memoryHit
        }

        // 2. Check Deduplication Queue
        lock.lock()
        if let existingTask = inFlightTasks[memKey] {
            lock.unlock()
            return await existingTask.value
        }

        // 3. Create Fetch & Decode Task
        let task = Task<UIImage?, Never>(priority: .userInitiated) { [weak self] in
            guard let self = self else { return nil }

            // Check L2 Disk Cache (stores raw untouched image bytes so high-res zoom decodes locally)
            let diskPath = self.diskCacheURL.appendingPathComponent(baseKey)
            if let data = try? Data(contentsOf: diskPath),
               let image = self.decodeAndDecompress(data: data, maxPixelSize: maxPixelSize) {
                let cost = Int(image.size.width * image.size.height * 4)
                self.memoryCache.setObject(image, forKey: keyNs, cost: cost)
                return image
            }

            // Fetch from Network
            do {
                var request = URLRequest(url: url)
                request.addValue("image/*", forHTTPHeaderField: "Accept")

                let (data, response) = try await self.session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    return nil
                }

                // Off-Thread Decode and Thumbnail Generation (Zero Main-Thread Hitching!)
                guard let decodedImage = self.decodeAndDecompress(data: data, maxPixelSize: maxPixelSize) else {
                    return nil
                }

                // Store into L1 Memory Cache
                let cost = Int(decodedImage.size.width * decodedImage.size.height * 4)
                self.memoryCache.setObject(decodedImage, forKey: keyNs, cost: cost)

                // Store into L2 Disk Cache (Asynchronously in background)
                Task.detached(priority: .background) {
                    try? data.write(to: diskPath, options: .atomic)
                }

                return decodedImage
            } catch {
                return nil
            }
        }

        inFlightTasks[memKey] = task
        lock.unlock()

        let result = await task.value

        lock.lock()
        inFlightTasks.removeValue(forKey: memKey)
        lock.unlock()

        return result
    }

    // MARK: - Proactive Batch Prefetching

    public func prefetch(urls: [URL?], maxPixelSize: CGFloat = 800) {
        for url in urls.compactMap({ $0 }) {
            if cachedImage(for: url, maxPixelSize: maxPixelSize) == nil {
                Task(priority: .utility) {
                    _ = await self.loadImage(for: url, maxPixelSize: maxPixelSize)
                }
            }
        }
    }

    // MARK: - Off-Thread Decompression & Downsampling Helper

    private func decodeAndDecompress(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return UIImage(data: data)
        }

        let options: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return UIImage(cgImage: cgThumb)
        }

        return UIImage(data: data)
    }

    // MARK: - Safe Deterministic Cache Key (SHA256)

    private func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Fast SwiftUI Cached Image Component with Silky-Smooth Transitions

public struct ShopAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL?
    private let maxPixelSize: CGFloat
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var loadedURL: URL?
    @State private var hasFailed: Bool = false

    public init(
        url: URL?,
        maxPixelSize: CGFloat = 800,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.content = content
        self.placeholder = placeholder

        // Synchronous L1 cache hit: if already loaded in memory, render IMMEDIATELY with 0ms delay!
        if let cached = ImageCacheManager.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            _uiImage = State(initialValue: cached)
            _loadedURL = State(initialValue: url)
        }
    }

    public var body: some View {
        ZStack {
            if let image = uiImage {
                content(Image(uiImage: image))
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else if hasFailed {
                placeholder()
                    .transition(.opacity)
            } else {
                placeholder()
                    .transition(.opacity)
            }
        }
        .animation(ShopMotion.imageFade, value: loadedURL?.absoluteString ?? (hasFailed ? "failed" : "loading"))
        .task(id: url) {
            guard let url = url else {
                uiImage = nil
                loadedURL = nil
                hasFailed = false
                return
            }
            if loadedURL == url, uiImage != nil { return }

            if let cached = ImageCacheManager.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
                withAnimation(ShopMotion.imageFade) {
                    self.uiImage = cached
                    self.loadedURL = url
                    self.hasFailed = false
                }
                return
            }

            if let loaded = await ImageCacheManager.shared.loadImage(for: url, maxPixelSize: maxPixelSize) {
                guard !Task.isCancelled else { return }
                withAnimation(ShopMotion.imageFade) {
                    self.uiImage = loaded
                    self.loadedURL = url
                    self.hasFailed = false
                }
            } else {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    self.hasFailed = true
                }
            }
        }
    }
}

// MARK: - Drop-in Compatibility Component with SwiftUI AsyncImage Phase API

public struct ShopCachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let maxPixelSize: CGFloat
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase
    @State private var loadedURL: URL?

    public init(
        url: URL?,
        maxPixelSize: CGFloat = 800,
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.content = content

        // Instant synchronous hit check
        if let cached = ImageCacheManager.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
            _loadedURL = State(initialValue: url)
        } else {
            _phase = State(initialValue: .empty)
            _loadedURL = State(initialValue: nil)
        }
    }

    private var animationKey: String {
        switch phase {
        case .success:
            return "success-\(loadedURL?.absoluteString ?? "")"
        case .failure:
            return "failure-\(url?.absoluteString ?? "")"
        case .empty:
            return "empty-\(url?.absoluteString ?? "")"
        @unknown default:
            return "unknown"
        }
    }

    public var body: some View {
        content(phase)
            .animation(ShopMotion.imageFade, value: animationKey)
            .task(id: url) {
                guard let url = url else {
                    phase = .empty
                    loadedURL = nil
                    return
                }
                if loadedURL == url, case .success = phase { return }

                // Instant L1 check on URL updates (e.g. reused views or variant switches)
                if let cached = ImageCacheManager.shared.cachedImage(for: url, maxPixelSize: maxPixelSize) {
                    withAnimation(ShopMotion.imageFade) {
                        self.phase = .success(Image(uiImage: cached))
                        self.loadedURL = url
                    }
                    return
                }

                if loadedURL != url {
                    self.phase = .empty
                }

                if let img = await ImageCacheManager.shared.loadImage(for: url, maxPixelSize: maxPixelSize) {
                    guard !Task.isCancelled else { return }
                    withAnimation(ShopMotion.imageFade) {
                        self.phase = .success(Image(uiImage: img))
                        self.loadedURL = url
                    }
                } else {
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        self.phase = .failure(URLError(.cannotDecodeContentData))
                        self.loadedURL = url
                    }
                }
            }
    }
}

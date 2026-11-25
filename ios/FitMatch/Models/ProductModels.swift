import Foundation

// MARK: - Dynamic Runtime Catalog Registry (Zero App Update for New Stores / Categories / Brands)

final class DynamicCatalogRegistry {
    static let shared = DynamicCatalogRegistry()

    private let storageKey = "fitmatch_dynamic_catalog_snapshot_v1"
    private let lock = NSLock()
    private var storesList: [ActiveStoreItem] = []
    private var storesByKey: [String: ActiveStoreItem] = [:]
    private var categoriesList: [DynamicCategoryItem] = []
    private var categoriesById: [String: DynamicCategoryItem] = [:]
    private var brandsList: [String] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ActiveStoresResponse.self, from: data) {
            apply(decoded)
        }
    }

    private func normalizeKey(_ raw: String) -> String {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    private func apply(_ response: ActiveStoresResponse) {
        var map: [String: ActiveStoreItem] = [:]
        for store in response.active_stores {
            let idLow = store.id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let nameLow = store.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !idLow.isEmpty {
                map[idLow] = store
                map[normalizeKey(idLow)] = store
            }
            if !nameLow.isEmpty {
                map[nameLow] = store
                map[normalizeKey(nameLow)] = store
            }
        }
        self.storesList = response.active_stores
        self.storesByKey = map

        if let cats = response.categories, !cats.isEmpty {
            self.categoriesList = cats
            self.categoriesById = Dictionary(uniqueKeysWithValues: cats.map { ($0.id.lowercased(), $0) })
        }
        if let brands = response.known_brands, !brands.isEmpty {
            self.brandsList = brands
        }
    }

    func update(from response: ActiveStoresResponse) {
        lock.lock()
        apply(response)
        lock.unlock()

        if let encoded = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    /// Updates store metadata directly from Supabase while preserving cached categories and brands.
    func updateStores(_ stores: [ActiveStoreItem]) {
        guard !stores.isEmpty else { return }
        lock.lock()
        let merged = ActiveStoresResponse(
            active_stores: stores,
            categories: categoriesList.isEmpty ? nil : categoriesList,
            known_brands: brandsList.isEmpty ? nil : brandsList
        )
        apply(merged)
        lock.unlock()

        if let encoded = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(encoded, forKey: storageKey)
        }
    }

    func storeItem(for identifier: String) -> ActiveStoreItem? {
        let low = identifier.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !low.isEmpty else { return nil }
        let norm = normalizeKey(low)
        lock.lock()
        defer { lock.unlock() }
        if let exact = storesByKey[low] ?? storesByKey[norm] {
            return exact
        }
        if norm.count >= 4 {
            return storesList.first {
                let sNorm = normalizeKey($0.id)
                let nNorm = normalizeKey($0.name)
                return (!sNorm.isEmpty && (norm.contains(sNorm) || sNorm.contains(norm)))
                    || (!nNorm.isEmpty && (norm.contains(nNorm) || nNorm.contains(norm)))
            }
        }
        return nil
    }

    func shippingRule(for storeId: String) -> (threshold: Double?, standard: Double)? {
        guard let item = storeItem(for: storeId) else { return nil }
        if item.free_shipping_threshold == nil && item.standard_shipping_cost == nil {
            return nil
        }
        return (
            threshold: item.free_shipping_threshold,
            standard: item.standard_shipping_cost ?? 4.90
        )
    }

    func categoryMeta(for catId: String) -> DynamicCategoryItem? {
        let low = catId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        return categoriesById[low]
    }

    func storeCountry(for storeId: String, storeName: String? = nil) -> String {
        if let item = storeItem(for: storeId) ?? storeName.flatMap({ storeItem(for: $0) }) {
            if let country = item.country?.trimmingCharacters(in: .whitespacesAndNewlines), !country.isEmpty {
                return country.uppercased()
            }
            let url = item.base_url.lowercased()
            if url.contains(".eu") || url.contains(".es") || url.contains(".de") || url.contains(".fr") {
                return "EU"
            }
        }
        let s = storeId.lowercased()
        let euFallback = ["top4", "depor", "alltricks", "warehouse", "tradeinn"]
        if euFallback.contains(where: { s.contains($0) }) {
            return "EU"
        }
        return "IT"
    }

    var cachedStores: [ActiveStoreItem] {
        lock.lock()
        defer { lock.unlock() }
        return storesList
    }

    var cachedCategories: [DynamicCategoryItem] {
        lock.lock()
        defer { lock.unlock() }
        return categoriesList
    }

    var allStoreIdentifiers: Set<String> {
        lock.lock()
        defer { lock.unlock() }
        var ids = Set<String>()
        for store in storesList {
            let idLow = store.id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let nameLow = store.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if !idLow.isEmpty { ids.insert(idLow) }
            if !nameLow.isEmpty { ids.insert(nameLow) }
        }
        return ids
    }

    var allBrands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return brandsList
    }
}

// MARK: - Brand Detection & Cleaning Helper

struct ProductBrandHelper {
    private static let fallbackBrands = [
        "Nike", "Adidas", "Asics", "Hoka", "Brooks", "Saucony", "Puma", "Mizuno",
        "New Balance", "Salomon", "On", "Garmin", "Polar", "Suunto", "Coros",
        "Under Armour", "La Sportiva", "Altra", "Compressport", "Oakley", "The North Face",
        "Jordan", "Babolat", "Wilson", "Head", "Yonex", "Tecnifibre", "Bullpadel", "Nox",
        "Atomic", "Rossignol", "Nordica", "Fischer", "Scarpa", "Tecnica", "Dalbello", "Lange",
        "Arena", "Speedo", "TYR", "Jaked", "Joma", "Diadora", "Lotto", "Uhlsport", "Reusch",
        "Macron", "Errea", "Kappa", "Spalding", "Molten", "Li-Ning", "Way of Wade", "Anta",
        "Maurten", "Enervit", "SiS", "NamedSport", "Dynafit", "Ortovox", "Black Diamond"
    ]

    static var knownBrands: [String] {
        let dynamic = DynamicCatalogRegistry.shared.allBrands
        if dynamic.isEmpty { return fallbackBrands }
        var seen = Set(fallbackBrands.map { $0.lowercased() })
        var merged = fallbackBrands
        for brand in dynamic {
            let low = brand.lowercased()
            if !seen.contains(low) {
                seen.insert(low)
                merged.append(brand)
            }
        }
        return merged
    }

    private static let fallbackStores: Set<String> = [
        "mister running", "misterrunning", "alltricks", "top4running", "maxi sport",
        "maxisport", "cisalfa", "cisalfa sport", "running warehouse", "runningwarehouse",
        "deporvillage", "sportler", "nencini", "nencini sport", "df sport specialist",
        "tradeinn", "decathlon", "sportit", "tennis-point", "tennis point",
        "basketball store", "basketballstore", "nonsolosport", "non solo sport",
        "intersport", "bshopzone"
    ]

    static var knownStores: Set<String> {
        fallbackStores.union(DynamicCatalogRegistry.shared.allStoreIdentifiers)
    }

    static func extractBrand(from text: String, fallback: String? = nil) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // 1. Check title/text against known brands
        for b in knownBrands {
            let bLow = b.lowercased()
            if lower.hasPrefix(bLow + " ") || lower == bLow || lower.contains(" " + bLow + " ") || lower.contains(bLow + "-") {
                return b
            }
        }

        // 2. If fallback is a valid brand and not a store name, use it
        if let fb = fallback?.trimmingCharacters(in: .whitespacesAndNewlines), !fb.isEmpty {
            let fbLow = fb.lowercased()
            if !knownStores.contains(fbLow) {
                for b in knownBrands {
                    if fbLow.contains(b.lowercased()) { return b }
                }
                return fb
            }
        }

        // 3. Fallback: check first word if not a generic Italian product word or store
        let words = trimmed.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        if let first = words.first, first.count >= 3 {
            let ignore = ["scarpe", "scarpa", "t-shirt", "maglia", "pantaloncini", "shorts", "giacca", "calze", "orologio"]
            if !ignore.contains(first.lowercased()) && !knownStores.contains(first.lowercased()) {
                return first
            }
        }

        return fallback ?? ""
    }
}

enum SizeMatchStatus: Int, Comparable {
    case available = 2
    case unknown = 1
    case unavailable = 0

    static func < (lhs: SizeMatchStatus, rhs: SizeMatchStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Offer: Identifiable, Codable, Hashable {
    var id: String { "\(store_id)_\(url)" }
    let store_id: String
    let store_name: String
    let product_id: String?
    let title: String
    let brand: String?
    let price: Double
    let original_price: Double?
    let discount_pct: Double?
    let savings: Double?
    let url: String
    let image_url: String?
    let gallery_images: [String]?
    let available_sizes: [String]?
    let variant_name: String?
    let in_stock: Bool?

    // Verified real shipping fields
    let shipping_cost: Double?
    let total_price: Double?
    let is_free_shipping: Bool?
    let shipping_label: String?
    let free_shipping_threshold: Double?
    let courier: String?

    init(
        store_id: String,
        store_name: String,
        product_id: String? = nil,
        title: String,
        brand: String? = nil,
        price: Double,
        original_price: Double? = nil,
        discount_pct: Double? = nil,
        savings: Double? = nil,
        url: String,
        image_url: String? = nil,
        gallery_images: [String]? = nil,
        available_sizes: [String]? = nil,
        variant_name: String? = nil,
        in_stock: Bool? = nil,
        shipping_cost: Double? = nil,
        total_price: Double? = nil,
        is_free_shipping: Bool? = nil,
        shipping_label: String? = nil,
        free_shipping_threshold: Double? = nil,
        courier: String? = nil
    ) {
        self.store_id = store_id
        self.store_name = store_name
        self.product_id = product_id
        self.title = title
        self.brand = brand
        self.price = price
        self.original_price = original_price
        self.discount_pct = discount_pct
        self.savings = savings
        self.url = url
        self.image_url = image_url
        self.gallery_images = gallery_images
        self.available_sizes = available_sizes
        self.variant_name = variant_name
        self.in_stock = in_stock
        self.shipping_cost = shipping_cost
        self.total_price = total_price
        self.is_free_shipping = is_free_shipping
        self.shipping_label = shipping_label
        self.free_shipping_threshold = free_shipping_threshold
        self.courier = courier
    }

    var displayVariant: String? {
        if let v = variant_name, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v
        }
        let parts = title.components(separatedBy: " - ")
        if parts.count > 1 {
            let col = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if col.count >= 3 { return col }
        }
        return nil
    }

    var effectiveBrand: String {
        ProductBrandHelper.extractBrand(from: title, fallback: brand)
    }

    var hasKnownSizes: Bool {
        !(available_sizes ?? []).isEmpty
    }

    func normalizedSizes() -> [String] {
        guard let sizes = available_sizes, !sizes.isEmpty else { return [] }
        return sizes.compactMap { s in
            var clean = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
            clean = clean.replacingOccurrences(of: "EU ", with: "")
            clean = clean.replacingOccurrences(of: " EU", with: "")
            clean = clean.replacingOccurrences(of: ".1/2", with: ".5")
            clean = clean.replacingOccurrences(of: " 1/2", with: ".5")
            clean = clean.replacingOccurrences(of: " 2/3", with: ".5")
            clean = clean.replacingOccurrences(of: " 1/3", with: ".5")
            clean = clean.replacingOccurrences(of: ".2/3", with: ".5")
            clean = clean.replacingOccurrences(of: ".1/3", with: ".5")
            // Convert decimal third-sizes from store catalogs (e.g. 42.7 -> 42.5, 43.3 -> 43.5)
            if clean.hasSuffix(".7") || clean.hasSuffix(".67") || clean.hasSuffix(".66") {
                if let val = Double(clean) {
                    clean = String(format: "%.1f", floor(val) + 0.5)
                }
            } else if clean.hasSuffix(".3") || clean.hasSuffix(".33") {
                if let val = Double(clean) {
                    clean = String(format: "%.1f", floor(val) + 0.5)
                }
            }
            if let dashIdx = clean.range(of: "- ")?.upperBound {
                clean = String(clean[dashIdx...]).trimmingCharacters(in: .whitespaces)
            }
            if let parenIdx = clean.firstIndex(of: "(") {
                clean = String(clean[..<parenIdx]).trimmingCharacters(in: .whitespaces)
            }
            clean = clean.trimmingCharacters(in: .whitespaces)
            return clean.isEmpty ? nil : clean
        }
    }

    func hasSize(_ targetSize: String?) -> Bool {
        guard let target = targetSize, !target.isEmpty else { return true }
        guard let sizes = available_sizes, !sizes.isEmpty else { return false }
        let normTarget = target.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        let normSizes = normalizedSizes()

        if normSizes.contains(normTarget) { return true }

        // Decimal shoe size proximity tolerance (e.g. 42.5 matches 42.7 or 42.66 within 0.35)
        if let dTarget = Double(normTarget) {
            for s in normSizes {
                if let dSize = Double(s), abs(dTarget - dSize) < 0.35 {
                    return true
                }
            }
            for raw in sizes {
                let cleanRaw = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                if let dRaw = Double(cleanRaw), abs(dTarget - dRaw) < 0.35 {
                    return true
                }
            }
        }

        let euToUs: [String: String] = [
            "36": "4.5", "36.5": "5", "37": "5", "37.5": "5.5", "38": "6", "38.5": "6",
            "39": "6.5", "39.5": "7", "40": "7", "40.5": "7.5", "41": "8", "41.5": "8.5", "42": "8.5",
            "42.5": "9", "43": "9.5", "43.5": "10", "44": "10", "44.5": "10.5", "45": "11",
            "45.5": "11.5", "46": "12", "46.5": "12.5", "47": "12.5", "47.5": "13", "48": "13.5",
            "48.5": "14", "49": "14.5"
        ]
        let usToEu = Dictionary(euToUs.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        if let us = euToUs[normTarget], normSizes.contains(us) { return true }
        if let eu = usToEu[normTarget], normSizes.contains(eu) { return true }

        return false
    }

    func sizeMatchStatus(_ targetSize: String?) -> SizeMatchStatus {
        guard let target = targetSize, !target.isEmpty else { return .available }
        guard hasKnownSizes else { return .unknown }
        return hasSize(target) ? .available : .unavailable
    }

    var calculatedShippingCost: Double {
        if let cost = shipping_cost { return cost }
        if let rule = DynamicCatalogRegistry.shared.shippingRule(for: store_id) {
            if let threshold = free_shipping_threshold ?? rule.threshold, price >= threshold {
                return 0.0
            }
            return rule.standard
        }
        let s = store_id.lowercased()
        let threshold: Double? = free_shipping_threshold ?? (
                        s.contains("tradeinn") ? nil :
                        (s.contains("cisalfa") || s.contains("maxi") || s.contains("nike")) ? 99.0 :
                        (s.contains("bshopzone") || s.contains("nencini") || s.contains("sportler") || s.contains("df_sport")) ? 100.0 :
                        s.contains("nonsolosport") ? 89.99 :
                        s.contains("depor") ? 80.0 :
                        s.contains("top4") ? 75.0 :
                        s.contains("alltricks") ? 69.0 :
                        s.contains("decathlon") ? 60.0 :
                        s.contains("sportit") ? 59.90 :
                        (s.contains("warehouse") || s.contains("tennis_point") || s.contains("intersport")) ? 59.0 :
                        (s.contains("basketball") || s.contains("adidas")) ? 50.0 : 49.0)
        let standard = s.contains("warehouse") || s.contains("bshopzone") ? 10.00 :
                       s.contains("cisalfa") ? 9.90 :
                       s.contains("df_sport") ? 8.00 :
                       s.contains("maxi") ? 7.90 :
                       s.contains("basketball") ? 6.90 :
                       (s.contains("sportit") || s.contains("tennis_point")) ? 5.99 :
                       (s.contains("nencini") || s.contains("intersport")) ? 5.90 :
                       (s.contains("nike") || s.contains("nonsolosport")) ? 5.00 :
                       (s.contains("alltricks") || s.contains("depor") || s.contains("decathlon") || s.contains("tradeinn") || s.contains("adidas")) ? 4.99 :
                       s.contains("sportler") ? 4.95 : 4.90
        if let threshold, price >= threshold {
            return 0.0
        }
        return standard
    }

    var calculatedTotalPrice: Double {
        total_price ?? (price + calculatedShippingCost)
    }

    var isFreeShipping: Bool {
        is_free_shipping ?? (calculatedShippingCost == 0.0)
    }

    var formattedShipping: String {
        if isFreeShipping {
            return "Sped. Gratis"
        }
        return String(format: "+ €%.2f sped.", calculatedShippingCost)
    }

    var formattedTotalPrice: String {
        String(format: "€%.2f", calculatedTotalPrice)
    }

    var formattedPrice: String {
        String(format: "€%.2f", price)
    }

    var formattedOriginalPrice: String? {
        guard let original_price = original_price, original_price > price else { return nil }
        return String(format: "€%.2f", original_price)
    }

    var discountBadge: String? {
        guard let discount_pct = discount_pct, discount_pct > 0 else { return nil }
        return String(format: "-%.0f%%", discount_pct)
    }

    var allImages: [String] {
        var imgs: [String] = []
        if let primary = image_url, !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imgs.append(primary)
        }
        if let g = gallery_images {
            for img in g where !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !imgs.contains(img) { imgs.append(img) }
            }
        }
        return imgs
    }
}

struct MatchedProduct: Identifiable, Codable, Hashable {
    let id_val: String?
    let canonical_name: String
    let brand: String?
    let image_url: String?
    let gallery_images: [String]?
    let gender: String?
    let offers: [Offer]
    let best_price: Double?
    let highest_price: Double?
    let cross_store_savings: Double?

    init(
        id_val: String? = nil,
        canonical_name: String,
        brand: String? = nil,
        image_url: String? = nil,
        gallery_images: [String]? = nil,
        gender: String? = nil,
        offers: [Offer] = [],
        best_price: Double? = nil,
        highest_price: Double? = nil,
        cross_store_savings: Double? = nil
    ) {
        self.id_val = id_val
        self.canonical_name = canonical_name
        self.brand = brand
        self.image_url = image_url
        self.gallery_images = gallery_images
        self.gender = gender
        self.offers = offers
        self.best_price = best_price
        self.highest_price = highest_price
        self.cross_store_savings = cross_store_savings
    }

    enum CodingKeys: String, CodingKey {
        case id_val = "id"
        case canonical_name
        case brand
        case image_url
        case gallery_images
        case gender
        case offers
        case best_price
        case highest_price
        case cross_store_savings
    }

    var allImages: [String] {
        var imgs: [String] = []
        if let primary = image_url, !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imgs.append(primary)
        }
        if let g = gallery_images {
            for img in g where !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !imgs.contains(img) { imgs.append(img) }
            }
        }
        for o in offers {
            for oImg in o.allImages {
                if !imgs.contains(oImg) { imgs.append(oImg) }
            }
        }
        return imgs
    }

    var id: String {
        if let iv = id_val, !iv.isEmpty {
            return iv
        }
        let g = gender ?? "unisex"
        let p = best_price != nil ? String(format: "%.2f", best_price!) : "0"
        return "\(canonical_name)_\(g)_\(p)"
    }

    var effectiveBrand: String {
        ProductBrandHelper.extractBrand(from: canonical_name, fallback: brand)
    }

    var displayTitle: String {
        let base = cleanTitle
        if let g = gender, !g.isEmpty && g.lowercased() != "unisex" && !base.lowercased().contains(g.lowercased()) {
            return "\(base) (\(g))"
        }
        return base
    }

    var cleanTitle: String {
        var base = canonical_name
        let b = effectiveBrand
        if !b.isEmpty {
            let pattern = "(?i)^(" + NSRegularExpression.escapedPattern(for: b) + "\\s+)+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(location: 0, length: base.utf16.count)
                base = regex.stringByReplacingMatches(in: base, options: [], range: range, withTemplate: "\(b) ")
            }
        }
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComparable: Bool {
        let text = (canonical_name + " " + (gender ?? "") + " " + offers.map { $0.title }.joined(separator: " ")).lowercased()
        let nonShoeKeywords = [
            "fascia", "porta ipod", "porta cellulare", "strap", "cintura", "marsupio",
            "calze", "socks", "maglia", "t-shirt", "pantaloncini", "shorts", "giacca",
            "cappellino", "guanti", "borraccia", "gel", "barretta", "integratore"
        ]
        for neg in nonShoeKeywords {
            if text.contains(neg) { return false }
        }
        let shoeKeywords = [
            "scarpa", "scarpe", "shoe", "shoes", "running", "trail", "sneaker",
            "zoom fly", "pegasus", "vomero", "invincible", "alphafly", "vaporfly",
            "ghost", "glycerin", "clifton", "bondi", "nimbus", "cumulus", "kayano",
            "novablast", "endorphin", "ride", "triumph", "adizero", "boston",
            "ultraboost", "supernova", "prodigio", "speedcross", "cloudmonster",
            "cloudsurfer", "forerunner", "fenix", "venu", "epix", "instinct",
            "coros", "polar", "suunto"
        ]
        for kw in shoeKeywords {
            if text.contains(kw) { return true }
        }
        return false
    }

    var allAvailableSizes: [String] {
        var set = Set<String>()
        for offer in offers {
            for s in offer.normalizedSizes() {
                if !s.isEmpty { set.insert(s) }
            }
        }
        if set.isEmpty {
            return []
        }
        return set.sorted { s1, s2 in
            if let d1 = Double(s1), let d2 = Double(s2) {
                return d1 < d2
            }
            return s1 < s2
        }
    }

    func bestOffer(for size: String?) -> Offer? {
        guard let sz = size, !sz.isEmpty else { return bestOffer }
        let matching = offers.filter { $0.hasSize(sz) }
        return matching.min(by: { $0.price < $1.price }) ?? bestOffer
    }

    var bestOffer: Offer? {
        offers.min(by: { $0.price < $1.price })
    }

    var formattedBestPrice: String {
        if let best_price = best_price {
            return String(format: "€%.2f", best_price)
        }
        return "N/D"
    }

    var formattedSavings: String? {
        guard let savings = cross_store_savings, savings > 1.0 else { return nil }
        return String(format: "Risparmi fino a €%.2f", savings)
    }
}

// MARK: - Price History & Market Trends

struct PriceHistoryPoint: Identifiable, Codable, Hashable {
    var id: String { "\(date)_\(store_name)_\(price)" }
    let date: String
    let price: Double
    let store_name: String
    let offer_id: String?

    var formattedPrice: String {
        String(format: "€%.2f", price)
    }

    var parsedDate: Date {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoFormatter.date(from: date) { return d }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let d = isoFormatter.date(from: date) { return d }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.date(from: date) ?? Date()
    }

    var shortDateLabel: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateFormat = "d MMM"
        return df.string(from: parsedDate)
    }

    var formattedDateFull: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "it_IT")
        df.dateFormat = "d MMMM"
        return df.string(from: parsedDate).capitalized
    }
}

struct PriceHistoryResponse: Codable {
    let canonical_name: String
    let product_id: String?
    let current_price: Double
    let lowest_price: Double
    let highest_price: Double
    let average_price: Double
    let is_all_time_low: Bool
    let price_drop_percentage: Double?
    let price_drop_amount: Double?
    let history_points: [PriceHistoryPoint]
    let total_data_points: Int
    let first_recorded_date: String?
    let last_recorded_date: String?

    var formattedCurrentPrice: String {
        String(format: "€%.2f", current_price)
    }

    var formattedLowestPrice: String {
        String(format: "€%.2f", lowest_price)
    }

    var formattedHighestPrice: String {
        String(format: "€%.2f", highest_price)
    }

    var formattedAveragePrice: String {
        String(format: "€%.2f", average_price)
    }

    var formattedSavingsVsAverage: String? {
        guard let diff = price_drop_amount, diff > 1.0 else { return nil }
        return String(format: "€%.2f sotto la media", diff)
    }
}

struct SearchResponse: Codable {
    let query: String
    let execution_time_seconds: Double
    let stores_queried: [String]
    let total_offers_found: Int
    let matched_products: [MatchedProduct]
}

struct AIRecommendation: Identifiable, Codable, Hashable {
    var id: String { product_name }
    let product_name: String
    let brand: String?
    let best_price: Double?
    let best_store: String?
    let original_price: Double?
    let discount_pct: Double?
    let link: String?
    let image_url: String?
    let cross_store_savings: Double?
    let all_offers: [AIOfferOption]
}

struct AIOfferOption: Identifiable, Codable, Hashable {
    var id: String { "\(store)_\(price)" }
    let store: String
    let price: Double
    let url: String
}

struct AIAdviceResponse: Codable {
    let category_name: String
    let category_description: String
    let biomechanical_reasoning: String
    let recommendations: [AIRecommendation]
}

struct TopSaving: Identifiable, Codable {
    var id: String { canonical_name }
    let canonical_name: String
    let brand: String?
    let min_price: Double
    let max_price: Double
    let savings: Double
    let store_count: Int
}

struct CatalogStatsResponse: Codable {
    let total_products: Int
    let total_offers: Int
    let multi_store_products: Int
    let brands_count: Int
    let top_savings: [TopSaving]
}

// MARK: - Deal Title Sanitizer & Filter Options

struct DealTitleSanitizer {
    private static let preservedAcronyms: Set<String> = [
        "GTX", "GPS", "NBA", "FG", "AG", "TF", "MG", "SG", "IC", "IN",
        "AMOLED", "SE", "TR", "FF", "GT", "SL", "XL", "XXL", "XXS", "XS",
        "UA", "2IN1", "3D", "UV", "SPF", "EAA", "BCAA", "PRO", "MAX", "AIR",
        "ACG", "DRY", "DRI", "FIT", "WR", "WP", "ISO", "HRM", "LED", "USB",
        "CTRL", "HRD", "ML10", "AT10", "XT", "RC", "LD", "SP", "MD", "GW",
        "BOA", "LYT", "PRD", "SW", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9",
        "2L", "3L", "II", "III", "IV", "VI", "VII", "VIII", "IX", "X", "XI", "XII",
        "XXII", "XXI", "XS/S", "M/L", "S/M", "L/XL", "W", "M"
    ]

    /// Decodes common named and numeric HTML entities (e.g. &nbsp;, &#xE0;, &#224;, &amp;)
    static func decodeHTMLEntities(_ raw: String) -> String {
        var s = raw
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&rsquo;", with: "'")
            .replacingOccurrences(of: "&lsquo;", with: "'")
            .replacingOccurrences(of: "&ndash;", with: "–")
            .replacingOccurrences(of: "&mdash;", with: "—")
            .replacingOccurrences(of: "&trade;", with: "™")
            .replacingOccurrences(of: "&reg;", with: "®")
            .replacingOccurrences(of: "&deg;", with: "°")
            .replacingOccurrences(of: "&agrave;", with: "à")
            .replacingOccurrences(of: "&egrave;", with: "è")
            .replacingOccurrences(of: "&eacute;", with: "é")
            .replacingOccurrences(of: "&igrave;", with: "ì")
            .replacingOccurrences(of: "&ograve;", with: "ò")
            .replacingOccurrences(of: "&ugrave;", with: "ù")

        // Generic hex entities: &#xE0;
        if s.contains("&#x") || s.contains("&#X"),
           let hexRegex = try? NSRegularExpression(pattern: #"&#[xX]([0-9a-fA-F]+);"#) {
            let matches = hexRegex.matches(in: s, range: NSRange(location: 0, length: s.utf16.count)).reversed()
            for match in matches {
                if let fullRange = Range(match.range, in: s),
                   let codeRange = Range(match.range(at: 1), in: s),
                   let scalarVal = UInt32(s[codeRange], radix: 16),
                   let scalar = UnicodeScalar(scalarVal) {
                    s.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }

        // Generic decimal entities: &#224;
        if s.contains("&#"),
           let decRegex = try? NSRegularExpression(pattern: #"&#([0-9]+);"#) {
            let matches = decRegex.matches(in: s, range: NSRange(location: 0, length: s.utf16.count)).reversed()
            for match in matches {
                if let fullRange = Range(match.range, in: s),
                   let codeRange = Range(match.range(at: 1), in: s),
                   let scalarVal = UInt32(s[codeRange]),
                   let scalar = UnicodeScalar(scalarVal) {
                    s.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }

        return s
    }

    /// Cleans noisy store titles: decodes HTML, normalizes ALL CAPS, removes duplicate brand echoes & extra whitespace.
    static func clean(_ rawTitle: String, brand: String? = nil, canonicalName: String? = nil) -> String {
        var s = decodeHTMLEntities(rawTitle)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if s.isEmpty, let canon = canonicalName?.trimmingCharacters(in: .whitespacesAndNewlines), !canon.isEmpty {
            s = decodeHTMLEntities(canon)
        }

        // Normalize shouting ALL CAPS titles (e.g. "SCARPE RUNNING ASICS METASPEED SP M")
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        if letters.count >= 8 {
            let upperCount = letters.filter { CharacterSet.uppercaseLetters.contains($0) }.count
            if Double(upperCount) / Double(letters.count) > 0.82 {
                s = smartTitleCase(s)
            }
        }

        // Collapse duplicated brand repetitions (e.g. "Puma Scarpe Puma MagMax NITRO 2", "adidas Performance adidas Scarpe...")
        if let rawBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines), !rawBrand.isEmpty {
            let escaped = NSRegularExpression.escapedPattern(for: rawBrand)
            // Remove trailing standalone brand echo ("... PUMA") if brand already appears earlier
            if let trailingRegex = try? NSRegularExpression(pattern: #"(?i)\s+\b"# + escaped + #"\b$"#) {
                let firstLoc = s.range(of: rawBrand, options: .caseInsensitive)?.lowerBound
                let lastRange = s.range(of: rawBrand, options: [.caseInsensitive, .backwards])
                if let firstLoc, let lastRange, firstLoc != lastRange.lowerBound {
                    s = trailingRegex.stringByReplacingMatches(
                        in: s,
                        range: NSRange(location: 0, length: s.utf16.count),
                        withTemplate: ""
                    ).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            // Collapse "Brand Performance Brand ..." or "Brand Scarpe Brand ..."
            if let midDupRegex = try? NSRegularExpression(pattern: #"(?i)^("# + escaped + #")\s+(?:(?:performance|scarpe(?:\s+da)?\s+\w+|scarpa(?:\s+da)?\s+\w+|orologio(?:\s+gps)?|smartwatch(?:\s+gps)?|racchetta(?:\s+da)?\s+\w+|gel\s+energetico|barrette?\s+energetiche?)\s+)+\1\b"#) {
                if midDupRegex.firstMatch(in: s, range: NSRange(location: 0, length: s.utf16.count)) != nil {
                    // Remove only the leading brand prefix so "Scarpe Brand Model" becomes clean "Brand Model"
                    if let leadRegex = try? NSRegularExpression(pattern: #"(?i)^"# + escaped + #"\s+"#) {
                        s = leadRegex.stringByReplacingMatches(
                            in: s,
                            range: NSRange(location: 0, length: s.utf16.count),
                            withTemplate: ""
                        )
                    }
                }
            }
        }

        return s
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips a redundant leading brand name when the brand is already rendered in its own eyebrow label.
    static func stripLeadingBrand(_ cleanedTitle: String, brand: String?) -> String {
        guard let b = brand?.trimmingCharacters(in: .whitespacesAndNewlines), !b.isEmpty else {
            return cleanedTitle
        }
        let escaped = NSRegularExpression.escapedPattern(for: b)
        let pattern = #"(?i)^"# + escaped + #"(?:\s+performance|\s+swim|\s+running)?[\s:\-–]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return cleanedTitle }
        let stripped = regex.stringByReplacingMatches(
            in: cleanedTitle,
            range: NSRange(location: 0, length: cleanedTitle.utf16.count),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.count >= 4 else { return cleanedTitle }
        return stripped.prefix(1).uppercased() + stripped.dropFirst()
    }

    private static func smartTitleCase(_ text: String) -> String {
        let lowerWords: Set<String> = ["da", "di", "del", "della", "dei", "delle", "per", "con", "su", "in", "a", "e", "o", "la", "il", "lo", "le", "gli", "un", "una", "x"]
        let words = text.components(separatedBy: " ")
        return words.enumerated().map { idx, word in
            let upper = word.uppercased()
            let cleanAlphaNum = upper.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            if preservedAcronyms.contains(cleanAlphaNum) {
                return upper
            }
            let lower = word.lowercased()
            if idx > 0 && lowerWords.contains(lower) {
                return lower
            }
            if lower.contains("-") {
                return lower.split(separator: "-", omittingEmptySubsequences: false)
                    .map { part -> String in
                        let pUp = String(part).uppercased()
                        if preservedAcronyms.contains(pUp) { return pUp }
                        return String(part).prefix(1).uppercased() + String(part).dropFirst()
                    }
                    .joined(separator: "-")
            }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }
}

enum DealsSortOption: String, CaseIterable, Identifiable, Hashable {
    case quality = "quality"
    case discount = "discount"
    case savings = "savings"
    case priceAsc = "price_asc"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quality: return "Consigliati"
        case .discount: return "Sconto più alto"
        case .savings: return "Maggior risparmio (€)"
        case .priceAsc: return "Prezzo crescente"
        }
    }

    var shortTitle: String {
        switch self {
        case .quality: return "Consigliati"
        case .discount: return "Sconto %"
        case .savings: return "Risparmio €"
        case .priceAsc: return "Prezzo ↑"
        }
    }

    var icon: String {
        switch self {
        case .quality: return "sparkles"
        case .discount: return "percent"
        case .savings: return "eurosign.circle"
        case .priceAsc: return "arrow.up"
        }
    }
}

struct DealsFilterOptions: Equatable, Hashable {
    var gender: String? = nil        // nil, "uomo", "donna", "unisex"
    var size: String? = nil          // e.g. "43", "M"
    var maxPrice: Double? = nil
    var minDiscount: Double? = nil
    var freeShippingOnly: Bool = false
    var includeKids: Bool = false
    var brand: String? = nil
    var sort: DealsSortOption = .quality

    var activeFilterCount: Int {
        var count = 0
        if let g = gender, !g.isEmpty { count += 1 }
        if let s = size, !s.isEmpty { count += 1 }
        if maxPrice != nil { count += 1 }
        if minDiscount != nil { count += 1 }
        if freeShippingOnly { count += 1 }
        if includeKids { count += 1 }
        if let b = brand, !b.isEmpty { count += 1 }
        if sort != .quality { count += 1 }
        return count
    }

    var isDefault: Bool {
        activeFilterCount == 0
    }

    var cacheKeySuffix: String {
        "\(gender ?? "")|\(size ?? "")|\(maxPrice.map { String(Int($0)) } ?? "")|\(minDiscount.map { String(Int($0)) } ?? "")|\(freeShippingOnly ? 1 : 0)|\(includeKids ? 1 : 0)|\(brand?.lowercased() ?? "")|\(sort.rawValue)"
    }
}

// MARK: - Shopify Shop-Style Store Showcase Models

struct StoreShowcaseProduct: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let brand: String?
    let image_url: String?
    let gallery_images: [String]?
    let available_sizes: [String]?
    let current_price: Double
    let original_price: Double?
    let discount_pct: Double?
    let product_url: String
    let canonical_name: String
    let product_id: String?
    let shipping_cost: Double?
    let total_price: Double?
    let is_free_shipping: Bool?
    let shipping_label: String?
    let free_shipping_threshold: Double?
    let courier: String?
    // Rich v2 deals & cross-store metadata
    let store_id: String?
    let store_name: String?
    let store_rating: String?
    let store_review_count: String?
    let store_logo_url: String?
    let product_category: String?
    let product_gender: String?
    let size_count: Int?
    let multi_store_count: Int?
    let market_min_price: Double?
    let is_best_market_price: Bool?
    let is_all_time_low: Bool?
    let price_drop_eur: Double?
    let deal_score: Double?
    let last_checked_at: String?

    init(
        id: String,
        title: String,
        brand: String? = nil,
        image_url: String? = nil,
        gallery_images: [String]? = nil,
        available_sizes: [String]? = nil,
        current_price: Double,
        original_price: Double? = nil,
        discount_pct: Double? = nil,
        product_url: String,
        canonical_name: String,
        product_id: String? = nil,
        shipping_cost: Double? = nil,
        total_price: Double? = nil,
        is_free_shipping: Bool? = nil,
        shipping_label: String? = nil,
        free_shipping_threshold: Double? = nil,
        courier: String? = nil,
        store_id: String? = nil,
        store_name: String? = nil,
        store_rating: String? = nil,
        store_review_count: String? = nil,
        store_logo_url: String? = nil,
        product_category: String? = nil,
        product_gender: String? = nil,
        size_count: Int? = nil,
        multi_store_count: Int? = nil,
        market_min_price: Double? = nil,
        is_best_market_price: Bool? = nil,
        is_all_time_low: Bool? = nil,
        price_drop_eur: Double? = nil,
        deal_score: Double? = nil,
        last_checked_at: String? = nil
    ) {
        self.id = id
        self.title = title
        self.brand = brand
        self.image_url = image_url
        self.gallery_images = gallery_images
        self.available_sizes = available_sizes
        self.current_price = current_price
        self.original_price = original_price
        self.discount_pct = discount_pct
        self.product_url = product_url
        self.canonical_name = canonical_name
        self.product_id = product_id
        self.shipping_cost = shipping_cost
        self.total_price = total_price
        self.is_free_shipping = is_free_shipping
        self.shipping_label = shipping_label
        self.free_shipping_threshold = free_shipping_threshold
        self.courier = courier
        self.store_id = store_id
        self.store_name = store_name
        self.store_rating = store_rating
        self.store_review_count = store_review_count
        self.store_logo_url = store_logo_url
        self.product_category = product_category
        self.product_gender = product_gender
        self.size_count = size_count
        self.multi_store_count = multi_store_count
        self.market_min_price = market_min_price
        self.is_best_market_price = is_best_market_price
        self.is_all_time_low = is_all_time_low
        self.price_drop_eur = price_drop_eur
        self.deal_score = deal_score
        self.last_checked_at = last_checked_at
    }

    var effectiveBrand: String {
        ProductBrandHelper.extractBrand(from: title, fallback: brand)
    }

    var cleanDisplayTitle: String {
        DealTitleSanitizer.clean(title, brand: effectiveBrand, canonicalName: canonical_name)
    }

    var titleWithoutLeadingBrand: String {
        DealTitleSanitizer.stripLeadingBrand(cleanDisplayTitle, brand: effectiveBrand)
    }

    var effectiveFreeShipping: Bool {
        if let free = is_free_shipping { return free }
        if let ship = shipping_cost { return ship == 0.0 }
        if let threshold = free_shipping_threshold, threshold > 0 {
            return current_price >= threshold
        }
        if let sid = store_id, let rule = DynamicCatalogRegistry.shared.shippingRule(for: sid),
           let threshold = rule.threshold, threshold > 0 {
            return current_price >= threshold
        }
        return false
    }

    var hasMultipleStores: Bool {
        (multi_store_count ?? 1) > 1
    }

    var isVerifiedAllTimeLow: Bool {
        is_all_time_low == true
    }

    var isVerifiedBestMarketPrice: Bool {
        is_best_market_price == true
    }

    var formattedPrice: String {
        String(format: "€%.2f", current_price)
    }

    var formattedOriginalPrice: String? {
        guard let original_price = original_price, original_price > current_price else { return nil }
        return String(format: "€%.2f", original_price)
    }

    var discountBadge: String? {
        if let discount_pct = discount_pct, discount_pct >= 5 {
            return String(format: "-%.0f%%", discount_pct)
        }
        if let orig = original_price, orig > current_price {
            let pct = ((orig - current_price) / orig) * 100.0
            if pct >= 5 {
                return String(format: "-%.0f%%", pct)
            }
        }
        return nil
    }

    var allImages: [String] {
        var imgs: [String] = []
        if let primary = image_url, !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            imgs.append(primary)
        }
        if let g = gallery_images {
            for img in g where !img.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !imgs.contains(img) { imgs.append(img) }
            }
        }
        return imgs
    }

    func toMatchedProduct(storeId: String, storeName: String) -> MatchedProduct {
        let resolvedStoreId = storeId.isEmpty ? (store_id ?? "") : storeId
        let resolvedStoreName = storeName.isEmpty ? (store_name ?? "Partner Store") : storeName
        let effBrand = ProductBrandHelper.extractBrand(from: title, fallback: brand)
        let cleanTitle = cleanDisplayTitle
        let offer = Offer(
            store_id: resolvedStoreId,
            store_name: resolvedStoreName,
            product_id: product_id,
            title: cleanTitle,
            brand: effBrand,
            price: current_price,
            original_price: original_price,
            discount_pct: discount_pct,
            savings: (original_price ?? current_price) - current_price,
            url: product_url,
            image_url: image_url,
            gallery_images: gallery_images,
            available_sizes: available_sizes ?? [],
            in_stock: true,
            shipping_cost: shipping_cost,
            total_price: total_price,
            is_free_shipping: effectiveFreeShipping,
            shipping_label: shipping_label,
            free_shipping_threshold: free_shipping_threshold,
            courier: courier
        )
        let resolvedProductId = (product_id?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? product_id!
            : "\(resolvedStoreId)_\(id)"
        let resolvedCanonical = canonical_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? cleanTitle
            : DealTitleSanitizer.clean(canonical_name, brand: effBrand)
        return MatchedProduct(
            id_val: resolvedProductId,
            canonical_name: resolvedCanonical,
            brand: effBrand,
            image_url: image_url,
            gallery_images: gallery_images,
            gender: product_gender,
            offers: [offer],
            best_price: current_price,
            highest_price: original_price ?? current_price,
            cross_store_savings: nil
        )
    }
}

struct StoreShowcase: Identifiable, Codable, Hashable {
    var id: String { store_id }
    let store_id: String
    let store_name: String
    let total_offers: Int
    let avg_discount: Double
    let rating: String
    let review_count: String?
    let card_theme: String?
    let accent_color: String?
    let logo_url: String?
    let promo_text: String?
    let products: [StoreShowcaseProduct]

    init(
        store_id: String,
        store_name: String,
        total_offers: Int,
        avg_discount: Double,
        rating: String,
        review_count: String? = nil,
        card_theme: String? = nil,
        accent_color: String? = nil,
        logo_url: String? = nil,
        promo_text: String? = nil,
        products: [StoreShowcaseProduct]
    ) {
        self.store_id = store_id
        self.store_name = store_name
        self.total_offers = total_offers
        self.avg_discount = avg_discount
        self.rating = rating
        self.review_count = review_count
        self.card_theme = card_theme
        self.accent_color = accent_color
        self.logo_url = logo_url
        self.promo_text = promo_text
        self.products = products
    }

    var formattedRatingWithReviews: String {
        let r = rating.replacingOccurrences(of: ".", with: ",")
        if let rev = review_count, !rev.isEmpty {
            return "\(r) ★ (\(rev))"
        }
        return "\(r) ★"
    }

    /// Dynamically computes an authentic, intelligent promo headline based on actual products, discounts, and category.
    func dynamicPromoSubtitle(category: String? = nil) -> String {
        return IntelligentPromoGenerator.generate(for: self, category: category)
    }
}

struct StoreShowcaseResponse: Codable {
    let showcases: [StoreShowcase]
}

struct StoreRatingBreakdown: Codable {
    let score: Double
    let positive_pct: String
    let review_count: String
    let platform: String
}

struct StoreCustomerReview: Identifiable, Codable, Hashable {
    var id: String
    let author: String
    let rating: Double
    let text: String
    let date: String

    init(id: String = UUID().uuidString, author: String, rating: Double, text: String, date: String) {
        self.id = id
        self.author = author
        self.rating = rating
        self.text = text
        self.date = date
    }

    enum CodingKeys: String, CodingKey {
        case id, author, rating, text, date
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(String.self, forKey: .id)) ?? UUID().uuidString
        self.author = (try? container.decode(String.self, forKey: .author)) ?? "Cliente Verificato"
        self.rating = (try? container.decode(Double.self, forKey: .rating)) ?? 5.0
        self.text = (try? container.decode(String.self, forKey: .text)) ?? ""
        self.date = (try? container.decode(String.self, forKey: .date)) ?? "Recentemente"
    }
}

struct StoreDetailResponse: Codable {
    let store_id: String
    let store_name: String
    let base_url: String
    let rating: String
    let review_count: String
    let description: String
    let full_description: String?
    let badges: [String]
    let highlights: [String]?
    let location: String?
    let shipping_info: String?
    let return_policy: String?
    let rating_breakdown: StoreRatingBreakdown?
    let total_offers: Int
    let avg_discount: Double
    let min_price: Double
    var products: [StoreShowcaseProduct]
    let contact_email: String?
    let contact_phone: String?
    let social_instagram: String?
    let privacy_policy_url: String?
    let terms_url: String?
    let refund_policy: String?
    let shipping_policy: String?
    let city_or_location: String?
    let customer_reviews: [StoreCustomerReview]?
    let customer_photos: [String]?
}

// MARK: - Smart Search (Shopify Shop Style)
struct SmartSearchChip: Identifiable, Codable, Hashable {
    let id: String
    let label: String
    let param_key: String
    let value: String
}

struct CuratedProductSection: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let products: [MatchedProduct]
}

struct SpotlightRecommendation: Identifiable, Codable, Hashable {
    var id: String { product.id }
    let product: MatchedProduct
    let badge_text: String?
    let highlights: [String]
}

struct ComparativeSpecCard: Identifiable, Codable, Hashable {
    var id: String {
        "\(product.id)_\(model_name)"
    }
    let product: MatchedProduct
    let model_name: String
    let ideal_for: String
    let strengths: String
    let section_title: String?
}

struct SmartSearchIntent: Codable, Hashable {
    let raw_query: String
    let search_mode: String?
    let is_deep_dive: Bool?
    let target_keywords: [String]?
    let brand: String?
    let category: String?
    let gender: String?
    let max_price: Double?
    let min_price: Double?
    let size: String?
    let features: [String]?
    let explanation: String?
    let source: String?
    let is_off_topic: Bool?
    let is_unsafe: Bool?
    let is_conversational_advice: Bool?
}

struct SmartSearchResponse: Codable {
    let search_mode: String?
    let is_deep_dive: Bool?
    let is_conversational_advice: Bool?
    let conversational_header: String?
    let conversational_summary: String?
    let searched_queries: [String]?
    let curated_sections: [CuratedProductSection]?
    let comparative_cards: [ComparativeSpecCard]?
    let featured_cards: [SpotlightRecommendation]?
    let spotlight: SpotlightRecommendation?
    let follow_up_suggestions: [String]?
    let intent: SmartSearchIntent?
    let chips: [SmartSearchChip]?
    let total_found: Int
    let has_more: Bool?
    let context_state: ChatSessionContextState?
    let results: [MatchedProduct]
    let is_off_topic: Bool?
    let is_unsafe: Bool?
    let session_id: String?
    let turn_id: String?
    let user_image_url: String?

    init(
        search_mode: String?,
        is_deep_dive: Bool?,
        is_conversational_advice: Bool?,
        conversational_header: String?,
        conversational_summary: String?,
        searched_queries: [String]?,
        curated_sections: [CuratedProductSection]?,
        comparative_cards: [ComparativeSpecCard]?,
        featured_cards: [SpotlightRecommendation]?,
        spotlight: SpotlightRecommendation?,
        follow_up_suggestions: [String]?,
        intent: SmartSearchIntent?,
        chips: [SmartSearchChip]?,
        total_found: Int,
        has_more: Bool? = nil,
        context_state: ChatSessionContextState? = nil,
        results: [MatchedProduct],
        is_off_topic: Bool?,
        is_unsafe: Bool?,
        session_id: String?,
        turn_id: String?,
        user_image_url: String?
    ) {
        self.search_mode = search_mode
        self.is_deep_dive = is_deep_dive
        self.is_conversational_advice = is_conversational_advice
        self.conversational_header = conversational_header
        self.conversational_summary = conversational_summary
        self.searched_queries = searched_queries
        self.curated_sections = curated_sections
        self.comparative_cards = comparative_cards
        self.featured_cards = featured_cards
        self.spotlight = spotlight
        self.follow_up_suggestions = follow_up_suggestions
        self.intent = intent
        self.chips = chips
        self.total_found = total_found
        self.has_more = has_more
        self.context_state = context_state
        self.results = results
        self.is_off_topic = is_off_topic
        self.is_unsafe = is_unsafe
        self.session_id = session_id
        self.turn_id = turn_id
        self.user_image_url = user_image_url
    }
}

struct SmartSearchLoadMoreResponse: Codable {
    let results: [MatchedProduct]
    let total_found: Int?
    let has_more: Bool?
    let load_more: Bool?
    let session_id: String?
}

// MARK: - Conversational Search Turn Model
struct SearchConversationTurn: Identifiable, Codable, Hashable {
    let id: String
    let query: String
    let isFollowUp: Bool
    var isConversationalAdvice: Bool
    var conversationalHeader: String
    var conversationalSummary: String
    var searchedQueries: [String]
    var smartIntent: SmartSearchIntent?
    var activeChips: [SmartSearchChip]
    var searchResults: [MatchedProduct]
    var curatedSections: [CuratedProductSection]
    var comparativeCards: [ComparativeSpecCard]
    var featuredCards: [SpotlightRecommendation]
    var spotlight: SpotlightRecommendation?
    var followUpSuggestions: [String]
    var userFeedback: Int?
    var showAiExplanation: Bool
    var error: String?
    var isOffTopic: Bool
    var isUnsafe: Bool
    var userImageURL: String?
    let timestamp: Date

    init(
        id: String = UUID().uuidString,
        query: String,
        isFollowUp: Bool,
        isConversationalAdvice: Bool = false,
        conversationalHeader: String,
        conversationalSummary: String,
        searchedQueries: [String] = [],
        smartIntent: SmartSearchIntent? = nil,
        activeChips: [SmartSearchChip] = [],
        searchResults: [MatchedProduct] = [],
        curatedSections: [CuratedProductSection] = [],
        comparativeCards: [ComparativeSpecCard] = [],
        featuredCards: [SpotlightRecommendation] = [],
        spotlight: SpotlightRecommendation? = nil,
        followUpSuggestions: [String] = [],
        userFeedback: Int? = nil,
        showAiExplanation: Bool = false,
        error: String? = nil,
        isOffTopic: Bool = false,
        isUnsafe: Bool = false,
        userImageURL: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.query = query
        self.isFollowUp = isFollowUp
        self.isConversationalAdvice = isConversationalAdvice
        self.conversationalHeader = conversationalHeader
        self.conversationalSummary = conversationalSummary
        self.searchedQueries = searchedQueries
        self.smartIntent = smartIntent
        self.activeChips = activeChips
        self.searchResults = searchResults
        self.curatedSections = curatedSections
        self.comparativeCards = comparativeCards
        self.featuredCards = featuredCards
        self.spotlight = spotlight
        self.followUpSuggestions = followUpSuggestions
        self.userFeedback = userFeedback
        self.showAiExplanation = showAiExplanation
        self.error = error
        self.isOffTopic = isOffTopic
        self.isUnsafe = isUnsafe
        self.userImageURL = userImageURL
        self.timestamp = timestamp
    }

    var effectiveFeaturedCards: [SpotlightRecommendation] {
        if !featuredCards.isEmpty {
            return featuredCards
        }
        if let spot = spotlight {
            return [spot]
        }
        return []
    }

    var productsForFeedback: [MatchedProduct] {
        var prods: [MatchedProduct] = []
        for sec in curatedSections {
            for p in sec.products {
                if !prods.contains(where: { $0.id == p.id }) {
                    prods.append(p)
                }
            }
        }
        for res in searchResults {
            if !prods.contains(where: { $0.id == res.id }) {
                prods.append(res)
            }
        }
        for fc in effectiveFeaturedCards {
            if !prods.contains(where: { $0.id == fc.product.id }) {
                prods.insert(fc.product, at: 0)
            }
        }
        return Array(prods.prefix(8))
    }
}

// MARK: - AI Model Comparison Models

struct ModelSpecs: Codable, Hashable {
    let name: String
    let brand: String?
    let drop_mm: Int?
    let weight_g: Int?
    let cushioning: String?
    let midsole: String?
    let plate: String?
    let ideal_use: String?
    let target_runner: String?
    let pros: [String]
    let cons: [String]
}

struct StoreOfferBrief: Codable, Hashable {
    let store_name: String
    let price: Double
    let original_price: Double?
    let url: String
    let is_free_shipping: Bool
    let total_price: Double

    var formattedPrice: String {
        String(format: "€%.2f", price)
    }
}

struct ModelMarketData: Codable, Hashable {
    let model_name: String
    let brand: String?
    let best_price: Double?
    let highest_price: Double?
    let best_store: String?
    let image_url: String?
    let total_offers: Int
    let cross_store_savings: Double?
    let top_offers: [StoreOfferBrief]

    var formattedBestPrice: String {
        guard let p = best_price else { return "N/D" }
        return String(format: "€%.2f", p)
    }
}

struct ModelComparisonResponse: Codable, Hashable {
    let model_a_specs: ModelSpecs
    let model_b_specs: ModelSpecs
    let model_a_market: ModelMarketData
    let model_b_market: ModelMarketData
    let key_differences: [String]
    let verdict_summary: String
    let winner_for_value: String
    let winner_for_performance: String
    let price_delta: Double?
    let source: String?
}

// MARK: - Dedicated Category Filter Matcher for Deals & Search

struct CategoryFilterMatcher {
    static func matches(title: String, category: String, dbCategory: String? = nil, dbGender: String? = nil, brand: String? = nil) -> Bool {
        let t = title.lowercased()
        let cat = category.lowercased()
        let lcat = dbCategory?.lowercased() ?? ""
        let lgender = dbGender?.lowercased() ?? ""
        let lbrand = brand?.lowercased() ?? ""
        if cat == "tutti" || cat.isEmpty { return true }

        if cat == "smartwatch" {
            let exc = ["racchetta", "padel", "siux", "craft pacer", "scarpe", "scarpa", "fleece", "buff", "bolt polar", "polartec", "pile", "fascia", "calzini", "short", "maglia", "canott", "watching", "polaroid", "guanti", "pantalon", "protezione", "vetro", "pellicola", "custodia", "cover", "cinturino", "strap", "supporto", "sostegno", "manubrio", "attacco", "adattatore", "cavo", "sensore", "ciclocomputer", "edge 5", "edge 8", "edge 10", "edge explore", "pacer ls"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lcat == "gps_watch" && !t.contains("fenix pro") { return true }
            let incStrong = ["smartwatch", "apple watch", "galaxy watch", "garmin", "suunto", "coros", "forerunner", "fenix", "epix", "cardiofrequenzimetro", "instinct", "vivoactive", "venu", "enduro", "orologio gps"]
            if incStrong.contains(where: { t.contains($0) }) { return true }
            if t.contains("polar") && ["grit", "vantage", "pacer", "ignite", "unite", "orologio", "gps", "cardio"].contains(where: { t.contains($0) }) {
                return true
            }
            return false
        }

        if cat == "running" {
            let exc = ["maglia", "maglietta", "pantalon", "short", "tight", "tights", "legging", "felpa", "giacca", "t-shirt", "tshirt", "canotta", "reggiseno", "bra", "calzin", "calze", "cassette", "gonna", "padel", "calcio", "calcetto", "bici", "mtb", "gravel", "ciabatt", "sandal", "scarpone", "smartwatch", "apple watch", "forerunner", "garmin", "suunto", "coros", "racchetta", "zaino", "borsone", "occhiali", "cappello", "guanti", "shinguard", "parastinchi"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if ["running_shoes", "trail_running"].contains(lcat) { return true }
            let inc = ["running", "scarpe running", "scarpe da corsa", "corsa", "maratona", "pegasus", "vomero", "vaporfly", "alphafly", "invincible", "zoom fly", "adizero", "supernova", "boston", "ultraboost", "clifton", "bondi", "rincon", "mach", "novablast", "nimbus", "cumulus", "kayano", "superblast", "ghost", "glycerin", "endorphin", "kinvara", "triumph", "ride", "deviate", "velocity nitro", "foreverrun", "magnify", "magmax", "cloudmonster", "cloudsurfer", "fresh foam", "fuelcell", "1080", "880", "infinite elite", "velociti", "kinabalu", "supertrac", "speedcross", "speedgoat"]
            if inc.contains(where: { t.contains($0) }) { return true }
            if lcat == "shoes" && ["hoka", "brooks", "saucony", "altra", "on", "mizuno", "asics"].contains(lbrand) {
                return true
            }
            return ["asics", "hoka", "brooks", "saucony", "mizuno"].contains(where: { t.contains($0) })
        }

        if cat == "abbigliamento" {
            let exc = ["scarpe", "scarpa", "sneaker", "smartwatch", "apple watch", "garmin", "occhiali", "borraccia", "racchetta", "bicicletta", "bici", "zaino"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if ["top", "pants", "jacket"].contains(lcat) { return true }
            let inc = ["maglia", "maglietta", "pantalon", "tshirt", "t-shirt", "felpa", "hoodie", "jacket", "giacca", "giubbotto", "piumino", "parka", "tight", "short", "top", "tee", "windbreaker", "guscio", "gilet", "pile", "tuta", "leggings", "canotta", "fleece", "reggiseno", "bra", "salopette"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "donna" {
            if ["uomo", "junior"].contains(lgender) { return false }
            let exc = ["uomo", "men", "man", "homme", "bambino", "bambina", "boy", "junior", "jr", "baby"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lgender == "donna" { return true }
            let inc = ["donna", "wmn", "women", "woman", "femme", "lady", "girl", "reggiseno", "bra"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "outdoor" {
            let exc = ["smartwatch", "apple watch", "forerunner", "racchetta", "padel", "calcio", "calcetto", "bicicletta", "bici"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if ["trail_running", "outdoor"].contains(lcat) { return true }
            let inc = ["trail", "trekking", "outdoor", "montagna", "alpinism", "hiking", "gore-tex", "goretex", "gtx", "salomon", "speedcross", "supertrac", "kinabalu", "hierro", "cascadia", "peregrine", "terrex", "scarpone", "wildhorse", "mafate", "speedgoat", "tecton", "la sportiva", "salewa", "dynafit", "patagonia", "columbia", "merrell", "bastoncini"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "fitness" {
            let exc = ["smartwatch", "apple watch", "orologio", "occhiali", "scarpe outdoor", "racchetta", "padel", "bici", "bicicletta", "ipod", "fascia porta", "push up", "ferretto"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if ["fitness", "trainer"].contains(lcat) { return true }
            let inc = ["fitness", "training", "gym", "palestra", "pesi", "manubri", "kettlebell", "crossfit", "metcon", "dropset", "yoga", "pilates", "tappetino", "leggings", "sports bra", "reggiseno sportivo", "tuta", "indoor", "cyclette"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "accessori" {
            let exc = ["scarpe", "scarpa", "maglia", "pantalone", "felpa", "giacca", "smartwatch", "orologio", "racchetta", "bici", "bicicletta"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if ["eyewear", "socks", "pack", "hydration", "strap", "case", "mount", "sensor"].contains(lcat) { return true }
            let inc = ["occhiali", "calzini", "calze", "guanti", "cappell", "beanie", "zaino", "borraccia", "soft flask", "sock", "belt", "marsupio", "headband", "visiera", "cinturino", "strap", "berretto", "borsone", "shinguard", "parastinchi", "ginocchier"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "uomo" {
            if ["donna", "junior"].contains(lgender) { return false }
            let exc = ["donna", "women", "woman", "wmn", "femme", "lady", "reggiseno", "bra", "bambino", "bambina", "junior", "jr", "baby"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lgender == "uomo" { return true }
            let inc = ["uomo", "men", "man", "homme"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "padel" {
            let exc = ["scarpe running", "smartwatch", "trail", "trekking", "bicicletta", "t-fight", "medvedev", "pure drive", "pure aero", "pro staff", "altra experience", "flow velociti", "salomon drx"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lcat == "padel" { return true }
            let inc = ["padel", "bullpadel", "nox", "siux", "starvie", "kuikma", "coello", "vertex", "metalbone", "adipower", "viper", "veron", "nova pro", "extreme motion", "flash pro", "racchetta bolt", "overgrip"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "cycling" || cat == "ciclismo" {
            let exc = ["hyperboost", "neo lumina", "neo daichi", "edge 75", "scarponi sci", "scarpe running", "trail running", "padel", "racchetta"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lcat == "cycling" { return true }
            let inc = ["ciclismo", "bicicletta", "bici", "e-bike", "ebike", "ciclocomputer", "edge 5", "edge 8", "edge 10", "edge explore", "karoo", "rullo", "smart trainer", "kickr", "flux", "tacx", "wahoo", "favero", "assioma", "kask", "castelli", "sportful", "santini", "assos", "northwave", "fizik", "salopette", "shimano", "campagnolo", "copertone", "mtb", "gravel", "pastiglie freno", "disco freno"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "calcio" || cat == "football_boots" {
            let exc = ["scarpe running", "scarpa da running", "scarpe da running", "trail", "padel", "racchetta", "basket", "tennis", "windbreaker", "giacca da corsa", "pegasus", "vapor glove", "vapor pro 3", "sci "]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lcat == "football_boots" { return true }
            let inc = ["calcio", "calcetto", "futsal", "scarpin", "guanti portiere", "mercurial", "superfly", "predator", "phantom gx", "phantom luna", "tiempo", "copa pure", "copa gloro", "top sala", "top flex", "parastinchi", "shinguard", "uhlsport", "reusch"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "tennis" {
            let exc = ["padel", "bullpadel", "nox ", "siux", "starvie", "kuikma", "calcio", "basket", "sci ", "running"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lcat == "tennis" { return true }
            let inc = ["tennis", "terra battuta", "babolat pure drive", "pure aero", "pure strike", "wilson blade", "pro staff", "wilson clash", "yonex ezone", "vcore", "percept", "gel-resolution", "court ff", "nikecourt", "barricade", "head speed", "radical mp", "gravity mp"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "basket" || cat == "basketball" {
            let exc = ["calcio", "calcetto", "padel", "tennis", "running", "trail", "sci "]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lcat == "basketball" || lcat == "basketball_shoes" { return true }
            let inc = ["basket", "basketball", "pallacanestro", "lebron", "kd ", "kobe", "luka", "curry", "giannis", "sabrina", "tatum", "harden", "air jordan", "spalding", "molten", "canotta nba", "lakers", "chicago bulls", "celtics"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "sci" || cat == "winter_sports" {
            let exc = ["scarpe running", "padel", "calcio", "basket", "tennis", "racchetta", "vezor", "vercors", "scarpe", "scarpa"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lcat == "winter_sports" { return true }
            let inc = ["sci ", "da sci", "scarpon", "snowboard", "maschera sci", "casco sci", "attacchi sci", "ciaspole", "atomic", "rossignol", "nordica", "dalbello", "tecnica mach", "fischer", "volkl", "burton", "dynastar", "hawx", "scialpinismo"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "nuoto" || cat == "swim" {
            let exc = ["scarpe", "scarpa", "trainer", "crossfit", "bici", "padel", "calcio", "racchetta"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lcat == "swim" { return true }
            let inc = ["nuoto", "piscina", "occhialini", "cuffia nuoto", "costume", "bikini", "jammer", "powerskin", "fastskin", "cobra ultra", "pinne", "muta", "arena", "speedo", "jaked", "nabaiji", "pull buoy", "tavoletta"]
            return inc.contains(where: { t.contains($0) })
        }

        if cat == "nutrizione" || cat == "nutrition" {
            let blockedDbCats = ["shoes", "running_shoes", "trail_running", "top", "pants", "jacket", "pack", "hydration", "socks", "gps_watch", "racket", "padel", "cycling", "football_boots", "basketball", "basketball_shoes", "winter_sports", "swim"]
            if blockedDbCats.contains(lcat) { return false }
            let exc = ["scarpe", "scarpa", "sneaker", "asics", "trabuco", "cumulus", "nimbus", "kayano", "gt-2000", "pantalon", "short", "pocket", "maglia", "maglietta", "t-shirt", "tshirt", "canotta", "felpa", "giacca", "cappell", "trucker", "calzin", "calze", "zaino", "marsupio", "borraccia", "bottiglia", "soft flask", "gelflask", "flask", "massagg", "foam roller", "theragun", "compex", "hyperice", "cintura"]
            if exc.contains(where: { t.contains($0) }) { return false }
            if lcat == "nutrition" { return true }
            let inc = ["gel energet", "gel isoton", "carbo gel", "liquid gel", "energy gel", "gel maurten", "enervit", "maurten", "namedsport", "named sport", "226ers", "ethicsport", "ethic sport", "4endurance", "high5", "powerbar", "proaction", "cetilar", "pro nutrition", "piu watt", "science in sport", "barretta", "barrette", "maltodestrin", "sali mineral", "integrator", "elettrolit", "proteine", "whey", "creatina", "bcaa", "aminoacid", "bevanda isoton", "bevanda energet", "drink mix", "pre-workout", "pre workout", "recovery drink", "tart cherry", "omega 3"]
            return inc.contains(where: { t.contains($0) })
        }

        // Dynamic fallback for categories added on backend / Supabase without an iOS update
        if let meta = DynamicCatalogRegistry.shared.categoryMeta(for: cat) {
            if let exc = meta.excluded_keywords, exc.contains(where: { t.contains($0.lowercased()) }) {
                return false
            }
            if !lcat.isEmpty {
                if lcat == cat { return true }
                if let dbCats = meta.db_categories, dbCats.map({ $0.lowercased() }).contains(lcat) {
                    return true
                }
            }
            if let keywords = meta.keywords, keywords.contains(where: { t.contains($0.lowercased()) }) {
                return true
            }
        }

        return lcat == cat || t.contains(cat)
    }
}

// MARK: - Persistent AI Chat Sessions & Messages

struct ChatSessionContextState: Codable, Hashable {
    let subject_query: String?
    let last_query: String?
    let last_keywords: [String]?
    let entity_tokens: [String]?
    let product_type: String?
    let brand: String?
    let excluded_brands: [String]?
    let sub_brand: String?
    let category: String?
    let gender: String?
    let max_price: Double?
    let min_price: Double?
    let size: String?
    let color: String?
    let store: String?
    let excluded_stores: [String]?
    let excluded_features: [String]?
    let sort_by: String?
    let free_shipping: Bool?
    let on_sale: Bool?
    let min_discount: Double?
    let features: [String]?
}

struct ChatSessionSummary: Identifiable, Codable, Hashable {
    let id: String
    let device_id: String
    let user_id: String?
    let chat_type: String?
    let title: String
    let subtitle: String?
    let preview_image_url: String?
    let turn_count: Int?
    let context_state: ChatSessionContextState?
    let is_archived: Bool?
    let created_at: String?
    let updated_at: String?

    var formattedUpdatedDate: String {
        guard let raw = updated_at ?? created_at, !raw.isEmpty else { return "Recente" }
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        guard let date = isoFrac.date(from: raw) ?? isoBasic.date(from: raw) else {
            return "Recente"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct ChatSessionsListResponse: Codable {
    let sessions: [ChatSessionSummary]
}

struct ChatTurnResultsSnapshot: Codable, Hashable {
    let results: [MatchedProduct]?
    let curated_sections: [CuratedProductSection]?
    let comparative_cards: [ComparativeSpecCard]?
    let featured_cards: [SpotlightRecommendation]?
    let searched_queries: [String]?
    let spotlight: SpotlightRecommendation?
}

struct ChatMessageRecord: Identifiable, Codable, Hashable {
    let id: String
    let session_id: String
    let turn_index: Int
    let query: String
    let is_follow_up: Bool?
    let is_conversational_advice: Bool?
    let conversational_header: String?
    let conversational_summary: String?
    let intent_json: SmartSearchIntent?
    let chips_json: [SmartSearchChip]?
    let results_snapshot_json: ChatTurnResultsSnapshot?
    let follow_up_suggestions_json: [String]?
    let user_feedback: Int?
    let is_off_topic: Bool?
    let is_unsafe: Bool?
    let user_image_url: String?
    let created_at: String?
}

struct ChatSessionDetail: Identifiable, Codable {
    let id: String
    let device_id: String
    let user_id: String?
    let chat_type: String?
    let title: String
    let subtitle: String?
    let preview_image_url: String?
    let turn_count: Int?
    let context_state: ChatSessionContextState?
    let is_archived: Bool?
    let created_at: String?
    let updated_at: String?
    let messages: [ChatMessageRecord]?
}

// MARK: - Live Smart Search Thinking Trace (SSE)

struct SearchThinkingStep: Identifiable, Equatable, Hashable {
    enum Status: String, Equatable, Hashable {
        case running
        case done
        case skipped
    }

    let id: String
    var status: Status
    var title: String
    var detail: String?
    var elapsedMs: Int?
}

struct SmartSearchPartialPayload: Decodable {
    let results: [MatchedProduct]
    let chips: [SmartSearchChip]?
    let searched_queries: [String]?
    let conversational_header: String?
    let total_found: Int?
    let has_more: Bool?
}

struct SmartSearchStreamEvent: Decodable {
    let type: String
    let id: String?
    let status: String?
    let title: String?
    let detail: String?
    let elapsed_ms: Int?
    let message: String?
    let data: SmartSearchResponse?
    let partial: SmartSearchPartialPayload?

    private enum CodingKeys: String, CodingKey {
        case type, id, status, title, detail, elapsed_ms, message, data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.detail = try container.decodeIfPresent(String.self, forKey: .detail)
        self.elapsed_ms = try container.decodeIfPresent(Int.self, forKey: .elapsed_ms)
        self.message = try container.decodeIfPresent(String.self, forKey: .message)
        if self.type == "products" {
            self.partial = try container.decodeIfPresent(SmartSearchPartialPayload.self, forKey: .data)
            self.data = nil
        } else if self.type == "result" {
            self.data = try container.decodeIfPresent(SmartSearchResponse.self, forKey: .data)
            self.partial = nil
        } else {
            self.data = nil
            self.partial = nil
        }
    }
}





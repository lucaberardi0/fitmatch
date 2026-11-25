import Foundation

/// Generates authentic, dynamic, and intelligent promotional headlines for store showcases.
/// Uses real indexed catalog data: actual maximum discounts, top featured brands,
/// category context, and authentic shipping thresholds.
struct IntelligentPromoGenerator {

    /// Grammatically correct Italian preposition before a percentage ("all'80%", "all'11%", "al 55%")
    static func upToPercent(_ pct: Int) -> String {
        let usesElision = pct == 8 || pct == 11 || (pct >= 80 && pct <= 89)
        return usesElision ? "all'\(pct)%" : "al \(pct)%"
    }

    static func generate(for showcase: StoreShowcase, category: String? = nil) -> String {
        // If a server-provided dynamic promo text already exists, respect it
        if let custom = showcase.promo_text, !custom.isEmpty {
            return custom
        }

        let cat = category?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? "tutti"
        let products = showcase.products

        // 1. Calculate Real Maximum Discount from actual visible products
        let discounts = products.compactMap { $0.discount_pct }.filter { $0 > 0 }
        let maxDisc = Int((discounts.max() ?? showcase.avg_discount).rounded())
        let discPhrase = upToPercent(maxDisc)

        // 2. Identify top brands present in this store's current selection
        let brands = products.compactMap { $0.brand }.filter {
            !$0.isEmpty && $0.lowercased() != showcase.store_name.lowercased()
        }
        let topBrand = mostFrequent(in: brands)

        // 3. Extract authentic free shipping threshold (product -> DynamicCatalogRegistry -> fallback)
        let freeThreshold: Int? = {
            if let t = products.compactMap({ $0.free_shipping_threshold }).first(where: { $0 > 0 }) {
                return Int(t.rounded())
            }
            if let rule = DynamicCatalogRegistry.shared.shippingRule(for: showcase.store_id),
               let t = rule.threshold, t > 0 {
                return Int(t.rounded())
            }
            let sid = showcase.store_id.lowercased()
            if sid == "deporvillage" { return 80 }
            if sid == "top4running" { return 75 }
            if sid == "alltricks" { return 69 }
            if sid == "misterrunning" { return 49 }
            if sid == "decathlon" { return 60 }
            if sid == "cisalfa" || sid == "maxisport" || sid == "nike" { return 99 }
            if sid == "nencini" || sid == "sportler" || sid == "df_sportspecialist" || sid == "bshopzone" { return 100 }
            if sid == "runningwarehouse" || sid == "intersport" || sid == "tennis_point" { return 59 }
            if sid == "adidas" || sid == "basketballstore" { return 50 }
            return nil
        }()

        // 4. Category-Specific Concise Claims
        if cat != "tutti" && !cat.isEmpty {
            switch cat {
            case "smartwatch":
                let hasGarmin = products.contains { $0.title.lowercased().contains("garmin") || ($0.brand ?? "").lowercased() == "garmin" }
                let hasPolar = products.contains { $0.title.lowercased().contains("polar") || ($0.brand ?? "").lowercased() == "polar" }
                let hasSuunto = products.contains { $0.title.lowercased().contains("suunto") || ($0.brand ?? "").lowercased() == "suunto" }

                if (hasGarmin && hasPolar) && maxDisc > 0 {
                    return "Garmin e Polar fino \(discPhrase)"
                } else if hasGarmin && maxDisc > 0 {
                    return "Garmin e GPS fino \(discPhrase)"
                } else if hasSuunto && maxDisc > 0 {
                    return "Sportwatch Suunto fino \(discPhrase)"
                } else if maxDisc > 0 {
                    return "Smartwatch GPS fino \(discPhrase)"
                } else if let threshold = freeThreshold {
                    return "Spedizione gratis da \(threshold) €"
                } else {
                    return "Dispositivi GPS con garanzia ufficiale"
                }

            case "running":
                if let brand = topBrand, maxDisc > 0 {
                    return "\(brand) e scarpe running fino \(discPhrase)"
                } else if maxDisc > 0 {
                    return "Scarpe running fino \(discPhrase)"
                } else if let threshold = freeThreshold {
                    return "Spedizione gratis da \(threshold) €"
                } else {
                    return "Scarpe da gara e allenamento"
                }

            case "abbigliamento":
                if maxDisc > 0 {
                    return "Abbigliamento tecnico fino \(discPhrase)"
                } else if let threshold = freeThreshold {
                    return "Spedizione gratis da \(threshold) €"
                } else {
                    return "Abbigliamento sportivo di stagione"
                }

            case "padel":
                if maxDisc > 0 {
                    return "Racchette e scarpe padel fino \(discPhrase)"
                } else if let threshold = freeThreshold {
                    return "Padel • Sped. gratis da \(threshold) €"
                } else {
                    return "Attrezzatura padel dei top brand"
                }

            case "cycling", "ciclismo":
                if maxDisc > 0 {
                    return "Ciclismo e accessori fino \(discPhrase)"
                } else if let threshold = freeThreshold {
                    return "Ciclismo • Sped. gratis da \(threshold) €"
                } else {
                    return "Componenti e abbigliamento bici"
                }

            case "outdoor":
                if maxDisc > 0 {
                    return "Trail e outdoor fino \(discPhrase)"
                } else if let threshold = freeThreshold {
                    return "Outdoor • Sped. gratis da \(threshold) €"
                } else {
                    return "Scarpe trail e attrezzatura montagna"
                }

            case "fitness":
                if maxDisc > 0 {
                    return "Fitness e training fino \(discPhrase)"
                } else {
                    return "Scarpe e attrezzatura palestra"
                }

            case "donna":
                if maxDisc > 0 {
                    return "Selezione donna fino \(discPhrase)"
                } else {
                    return "Calzature e abbigliamento donna"
                }

            case "uomo":
                if maxDisc > 0 {
                    return "Selezione uomo fino \(discPhrase)"
                } else {
                    return "Calzature e abbigliamento uomo"
                }

            case "accessori":
                if maxDisc > 0 {
                    return "Occhiali e accessori fino \(discPhrase)"
                } else {
                    return "Accessori tecnici sportivi"
                }

            default:
                if maxDisc > 0 {
                    return "Sconti verificati fino \(discPhrase)"
                } else {
                    return "Selezione \(cat.capitalized) ai migliori prezzi"
                }
            }
        }

        // 5. General ("Tutte") Concise Data-Driven Copy
        let atlCount = products.filter { $0.isVerifiedAllTimeLow }.count
        let bestPriceCount = products.filter { $0.isVerifiedBestMarketPrice }.count

        if maxDisc > 0 {
            if atlCount >= 2 {
                return "Fino \(discPhrase) • \(atlCount) minimi storici"
            } else if bestPriceCount >= 2 {
                return "Fino \(discPhrase) • Miglior prezzo garantito"
            } else if let threshold = freeThreshold {
                return "Sconti fino \(discPhrase) • Sped. gratis da \(threshold) €"
            } else if let brand = topBrand {
                return "Sconti fino \(discPhrase) su \(brand) e top brand"
            } else {
                return "Offerte verificate fino \(discPhrase)"
            }
        } else if let threshold = freeThreshold {
            return "Spedizione gratis da \(threshold) €"
        } else {
            return "Rivenditore partner verificato"
        }
    }

    private static func mostFrequent(in list: [String]) -> String? {
        guard !list.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for item in list {
            counts[item, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}

import Foundation

/// Generates authentic, dynamic, and intelligent promotional headlines for store showcases.
/// Uses real indexed catalog data: actual maximum discounts, top featured brands,
/// category context, and authentic shipping thresholds.
struct IntelligentPromoGenerator {

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

        // 2. Identify top brands present in this store's current selection
        let brands = products.compactMap { $0.brand }.filter {
            !$0.isEmpty && $0.lowercased() != showcase.store_name.lowercased()
        }
        let topBrand = mostFrequent(in: brands)

        // 3. Extract authentic free shipping threshold (if available from products or store data)
        let freeThreshold: Int? = {
            if let t = products.compactMap({ $0.free_shipping_threshold }).first(where: { $0 > 0 }) {
                return Int(t.rounded())
            }
            // Store fallback shipping rule known values
            let sid = showcase.store_id.lowercased()
            if sid == "deporvillage" { return 80 }
            if sid == "top4running" { return 75 }
            if sid == "alltricks" { return 69 }
            if sid == "misterrunning" { return 49 }
            if sid == "decathlon" { return 50 }
            if sid == "cisalfa" { return 99 }
            if sid == "maxisport" { return 99 }
            if sid == "nencini" { return 100 }
            if sid == "runningwarehouse" { return 59 }
            return nil
        }()

        // 4. Category-Specific Intelligent Claims (Real-time contextual adaptation)
        if cat != "tutti" && !cat.isEmpty {
            switch cat {
            case "smartwatch":
                let hasGarmin = products.contains { $0.title.lowercased().contains("garmin") }
                let hasPolar = products.contains { $0.title.lowercased().contains("polar") }
                let hasSuunto = products.contains { $0.title.lowercased().contains("suunto") }

                if (hasGarmin && hasPolar) && maxDisc > 0 {
                    return "Garmin e Polar scontati fino al -\(maxDisc)%"
                } else if hasGarmin && maxDisc > 0 {
                    return "Offerte Garmin e GPS fino al -\(maxDisc)%"
                } else if hasSuunto && maxDisc > 0 {
                    return "Sportwatch Suunto fino al -\(maxDisc)%"
                } else if maxDisc > 0 {
                    return "Smartwatch e sportwatch fino al -\(maxDisc)%"
                } else if let threshold = freeThreshold {
                    return "Smartwatch con spedizione gratis da \(threshold) €"
                } else {
                    return "Dispositivi GPS e cardio con garanzia ufficiale"
                }

            case "running":
                if let brand = topBrand, maxDisc > 0 {
                    return "Scarpe \(brand) e running fino al -\(maxDisc)%"
                } else if maxDisc > 0 {
                    return "Risparmia fino al \(maxDisc)% sui saldi running"
                } else if let threshold = freeThreshold {
                    return "Scarpe da corsa con spedizione gratis da \(threshold) €"
                } else {
                    return "Scarpe da gara e allenamento ai migliori prezzi"
                }

            case "abbigliamento":
                if maxDisc > 0 {
                    return "Abbigliamento tecnico con sconti fino al -\(maxDisc)%"
                } else if let threshold = freeThreshold {
                    return "Completi e tute con spedizione gratis da \(threshold) €"
                } else {
                    return "Abbigliamento sportivo ufficiale di stagione"
                }

            case "padel":
                if maxDisc > 0 {
                    return "Racchette e abbigliamento padel fino al -\(maxDisc)%"
                } else if let threshold = freeThreshold {
                    return "Attrezzatura padel con spedizione gratis da \(threshold) €"
                } else {
                    return "Racchette e borse padel delle migliori marche"
                }

            case "cycling", "ciclismo":
                if maxDisc > 0 {
                    return "Ciclismo e accessori bici con sconti fino al -\(maxDisc)%"
                } else if let threshold = freeThreshold {
                    return "Componenti e abbigliamento bici con sped. gratis da \(threshold) €"
                } else {
                    return "Accessori e caschi ciclismo certificati"
                }

            case "outdoor":
                if maxDisc > 0 {
                    return "Trekking e scarpe da trail fino al -\(maxDisc)%"
                } else if let threshold = freeThreshold {
                    return "Attrezzatura outdoor con spedizione gratis da \(threshold) €"
                } else {
                    return "Scarponi e abbigliamento outdoor garantito"
                }

            case "fitness":
                if maxDisc > 0 {
                    return "Fitness e training con sconti fino al -\(maxDisc)%"
                } else {
                    return "Attrezzatura palestra e pesi ai migliori prezzi"
                }

            case "donna":
                if maxDisc > 0 {
                    return "Collezione donna con sconti fino al -\(maxDisc)%"
                } else {
                    return "Abbigliamento e calzature donna certificate"
                }

            case "uomo":
                if maxDisc > 0 {
                    return "Collezione uomo con sconti fino al -\(maxDisc)%"
                } else {
                    return "Abbigliamento e scarpe uomo in promozione"
                }

            case "accessori":
                if maxDisc > 0 {
                    return "Occhiali e accessori tecnici fino al -\(maxDisc)%"
                } else {
                    return "Accessori sportivi con garanzia ufficiale"
                }

            default:
                // Completely generic & flexible for any new category added in the future!
                if maxDisc > 0 {
                    return "Offerte \(cat.capitalized) con sconti reali fino al -\(maxDisc)%"
                } else {
                    return "Selezione speciale \(cat.capitalized) ai migliori prezzi"
                }
            }
        }

        // 5. General ("Tutte" / All Holiday Deals) Real Data Driven Copy
        if maxDisc >= 70 {
            if let threshold = freeThreshold {
                return "Risparmia fino al \(maxDisc)% • Spedizione gratis da \(threshold) €"
            } else if let brand = topBrand {
                return "Saldi fino al \(maxDisc)% su \(brand) e top brand"
            } else {
                return "Risparmia fino al \(maxDisc)% sui saldi di stagione"
            }
        } else if maxDisc >= 40 {
            if let threshold = freeThreshold {
                return "Sconti fino al \(maxDisc)% e spedizione gratis da \(threshold) €"
            } else if let brand = topBrand {
                return "Sconti fino al \(maxDisc)% su modelli \(brand) selezionati"
            } else {
                return "Risparmia fino al \(maxDisc)% su \(products.count)+ articoli in saldo"
            }
        } else if maxDisc > 0 {
            if let threshold = freeThreshold {
                return "Prezzi ribassati fino al -\(maxDisc)% • Sped. gratis da \(threshold) €"
            } else {
                return "Offerte selezionate con sconti fino al -\(maxDisc)%"
            }
        } else if let threshold = freeThreshold {
            return "Spedizione gratuita su ordini superiori a \(threshold) €"
        } else {
            return "Rivenditore autorizzato con stock ufficiale garantito"
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

import SwiftUI

// MARK: - Legal Documents (Privacy, Termini, Trasparenza Affiliazioni, Licenze)

enum AccountLegalType: String, Identifiable {
    case privacy
    case terms
    case affiliate
    case licenses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: return "Informativa sulla Privacy"
        case .terms: return "Termini e condizioni"
        case .affiliate: return "Comparazione e Affiliazioni"
        case .licenses: return "Licenze e attribuzioni"
        }
    }
}

enum FitMatchContactInfo {
    static let supportEmail = "support@fitmatch.it"
    static let privacyEmail = "privacy@fitmatch.it"
}

private struct LegalClause: Identifiable {
    let id = UUID()
    let heading: String
    let body: String
}

struct AccountLegalDocumentContent: View {
    let type: AccountLegalType
    let storeCount: Int

    private var lastUpdated: String { "Aggiornamento: Novembre 2026" }

    private var clauses: [LegalClause] {
        switch type {
        case .privacy:
            return [
                LegalClause(
                    heading: "1. Titolare del trattamento e contatti",
                    body: "Il trattamento dei dati personali raccolti tramite l'applicazione iOS FitMatch è effettuato dal progetto software FitMatch (sviluppatore Luca Berardi, Italia) in conformità al Regolamento (UE) 2016/679 (GDPR) e al D.Lgs. 196/2003 (Codice Privacy).\nContatto privacy e diritti dell'interessato: \(FitMatchContactInfo.privacyEmail)"
                ),
                LegalClause(
                    heading: "2. Categorie di dati trattati",
                    body: "• Dati di account (facoltativi): indirizzo email e identificativo univoco in caso di registrazione/accesso tramite Email o Accedi con Apple (con token protetti nel Portachiavi iOS).\n• Identificativo tecnico pseudonimo (device_id): UUID generato localmente per consentire il salvataggio in modalità ospite.\n• Preferenze sportive e misure: nome visualizzato, taglia scarpe EU, taglia abbigliamento, discipline sportive, brand preferiti e soglia sconto.\n• Dati di utilizzo in-app: prodotti salvati in wishlist, collezioni, avvisi prezzo, negozi seguiti/nascosti, cronologia visti di recente, sessioni dell'Assistente AI, recensioni e segnalazioni store inviate volontariamente.\n• Dati tecnici di notifica e redirect: token push APNs (solo previa autorizzazione) e parametro tecnico pseudonimo di attribuzione click (CUID) verso i siti dei negozi partner."
                ),
                LegalClause(
                    heading: "3. Finalità e basi giuridiche (art. 6 GDPR)",
                    body: "• Esecuzione del servizio richiesto (art. 6.1.b): comparazione prezzi e taglie, gestione wishlist, collezioni, preferenze e sincronizzazione cloud.\n• Consenso esplicito (art. 6.1.a): invio di notifiche push su cali prezzo e offerte, sempre revocabile da \"Notifiche\" o dalle Impostazioni iOS.\n• Legittimo interesse (art. 6.1.f): sicurezza dell'infrastruttura, prevenzione di abusi o spam sulle recensioni e miglioramento della rilevanza della ricerca."
                ),
                LegalClause(
                    heading: "4. Destinatari, infrastruttura e trasferimenti",
                    body: "FitMatch non vende né cede dati personali a terzi per pubblicità profilata. Per erogare il servizio utilizza:\n• Supabase: autenticazione, Edge Functions e database cloud con isolamento per utente (RLS).\n• Render (regione UE - Francoforte): backend FastAPI per sincronizzazione cataloghi e monitoraggio prezzi.\n• Provider AI (OpenRouter): elaborazione delle sole query testuali sportive per l'Assistente AI, senza invio di email o dati identificativi dell'utente.\n• Apple APNs: recapito delle notifiche push.\n• Sovrn //Commerce: gestione tecnica opzionale dei redirect affiliati verso i negozi partner tramite CUID pseudonimo."
                ),
                LegalClause(
                    heading: "5. Conservazione e cancellazione dei dati",
                    body: "I dati rimangono conservati finché utilizzi l'app o mantieni attivo l'account. Puoi svuotare in qualsiasi momento la cache locale, archiviare le chat AI oppure eliminare definitivamente l'account di autenticazione e tutti i dati cloud dalla sezione \"Dati e privacy\"."
                ),
                LegalClause(
                    heading: "6. Diritti dell'interessato (artt. 15–22 GDPR)",
                    body: "Hai diritto di accedere ai tuoi dati, rettificarli, ottenerne la portabilità in formato JSON strutturato (funzione \"Esporta i tuoi dati\"), opporti o chiederne la cancellazione immediata (\"Elimina Account & Tutti i Dati\"). Per richieste specifiche scrivi a \(FitMatchContactInfo.privacyEmail). Resta fermo il diritto di proporre reclamo al Garante per la Protezione dei Dati Personali (garanteprivacy.it)."
                )
            ]
        case .terms:
            return [
                LegalClause(
                    heading: "1. Oggetto del servizio",
                    body: "FitMatch è una piattaforma informativa e di comparazione prezzi dedicata ad articoli sportivi, calzature running/outdoor, smartwatch GPS e abbigliamento tecnico su \(storeCount) negozi partner verificati."
                ),
                LegalClause(
                    heading: "2. Ruolo di FitMatch (nessuna vendita diretta)",
                    body: "FitMatch non è un negozio online, non vende direttamente alcun prodotto, non elabora pagamenti e non gestisce spedizioni, resi o garanzie legali. Ogni contratto di compravendita si conclude esclusivamente tra l'utente e il rivenditore partner terzo selezionato."
                ),
                LegalClause(
                    heading: "3. Accuratezza di prezzi, sconti e taglie",
                    body: "Prezzi, percentuali di sconto, costi di spedizione e disponibilità delle taglie sono aggiornati periodicamente tramite sincronizzazione dai cataloghi dei negozi partner. Poiché i listini possono variare in tempo reale sui siti dei rivenditori, fanno sempre fede il prezzo finale e la disponibilità mostrati sul sito del venditore prima del pagamento."
                ),
                LegalClause(
                    heading: "4. Assistente AI e suggerimenti tecnici",
                    body: "Le risposte generate dall'Assistente AI e i filtri di abbinamento taglia/sport hanno finalità puramente orientative e informative. Non costituiscono consulenza medica, fisioterapica, ortopedica o professionale."
                ),
                LegalClause(
                    heading: "5. Account, modalità ospite e condotta",
                    body: "Puoi utilizzare FitMatch come ospite oppure registrare un account per sincronizzare i dati. L'utente si impegna a non effettuare scraping automatizzato, richieste abusive verso le API o pubblicazioni di recensioni false o offensive verso i negozi."
                ),
                LegalClause(
                    heading: "6. Proprietà intellettuale",
                    body: "Il codice, l'interfaccia grafica e i testi originali di FitMatch sono protetti dalle vigenti norme sul diritto d'autore. I marchi commerciali, i loghi e le immagini prodotto appartengono ai rispettivi proprietari."
                ),
                LegalClause(
                    heading: "7. Limitazione di responsabilità e legge applicabile",
                    body: "Nei limiti consentiti dalla legge, FitMatch non risponde di eventuali disservizi dei siti terzi o variazioni improvvise di prezzo successive all'ultimo aggiornamento. I presenti Termini sono regolati dalla legge italiana, fatti salvi i diritti inderogabili riconosciuti ai consumatori dal D.Lgs. 206/2005 (Codice del Consumo)."
                )
            ]
        case .affiliate:
            return [
                LegalClause(
                    heading: "1. Trasparenza del ranking (Direttiva Omnibus)",
                    body: "Nella sezione \"Per te\" e nei risultati di ricerca, FitMatch ordina prodotti e negozi sulla base di criteri oggettivi e personalizzati: corrispondenza con la taglia preferita dell'utente, brand e sport selezionati, entità dello sconto e completezza/affidabilità del catalogo. Nessun negozio può acquistare posizionamenti occulti nei risultati di comparazione."
                ),
                LegalClause(
                    heading: "2. Prezzi precedenti e percentuali di sconto",
                    body: "Le percentuali di sconto e i prezzi barrati mostrati nelle schede prodotto derivano dai prezzi di riferimento/listino comunicati dai rispettivi store partner o dallo storico prezzi registrato da FitMatch."
                ),
                LegalClause(
                    heading: "3. Link affiliati e sostenibilità del servizio",
                    body: "FitMatch è gratuito per gli utenti. Alcuni collegamenti in uscita verso i negozi partner possono utilizzare reti di affiliazione (tra cui Sovrn //Commerce) con un identificativo tecnico di click anonimo (CUID). Se completi un acquisto dopo il reindirizzamento, FitMatch può ricevere una commissione dal rivenditore senza alcun costo aggiuntivo né maggiorazione di prezzo per te."
                )
            ]
        case .licenses:
            return [
                LegalClause(
                    heading: "1. Tecnologie Apple iOS",
                    body: "L'applicazione è sviluppata nativamente in Swift per iOS utilizzando framework di sistema Apple: SwiftUI, AuthenticationServices (Accedi con Apple), Security (Keychain), UserNotifications, Charts, BackgroundTasks e CryptoKit."
                ),
                LegalClause(
                    heading: "2. Servizi e librerie di supporto",
                    body: "• FastAPI & Python ecosystem (backend API e normalizzazione cataloghi)\n• Supabase PostgREST, Edge Functions & GoTrue Auth (persistenza dati e autenticazione)\n• URLSession & ImageIO (cache locale immagini e rete)"
                ),
                LegalClause(
                    heading: "3. Marchi e contenuti di terze parti",
                    body: "Tutti i nomi commerciali, i loghi dei \(storeCount) negozi sportivi partner, i nomi dei brand (es. Nike, Asics, Garmin, Hoka, Salomon, Brooks, New Balance e altri) e le immagini dei prodotti sono di proprietà dei rispettivi titolari e vengono visualizzati esclusivamente a scopo descrittivo e di comparazione prezzi."
                )
            ]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(type.title)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundColor(.shopDark)

                Text(lastUpdated)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.shopPurpleLight)
                    .clipShape(Capsule())
            }

            ForEach(clauses) { clause in
                VStack(alignment: .leading, spacing: 6) {
                    Text(clause.heading)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.shopDark)

                    Text(clause.body)
                        .font(.system(size: 13.5))
                        .foregroundColor(.shopTextMuted)
                        .lineSpacing(3.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.shopBorder.opacity(0.65), lineWidth: 1)
                )
            }
        }
    }
}

struct AccountLegalDocumentPage: View {
    let type: AccountLegalType
    let storeCount: Int

    var body: some View {
        VStack(spacing: 0) {
            AccountSubPageHeader(title: type.title)

            ScrollView(showsIndicators: false) {
                AccountLegalDocumentContent(type: type, storeCount: storeCount)
                    .padding(.horizontal, ShopLayout.screenPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 32)
            }
        }
        .background(Color.shopSurface.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}

struct AccountLegalSheetView: View {
    let type: AccountLegalType
    let storeCount: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                AccountLegalDocumentContent(type: type, storeCount: storeCount)
                    .padding(ShopLayout.screenPadding)
                    .padding(.bottom, 24)
            }
            .background(Color.shopSurface.ignoresSafeArea())
            .navigationTitle(type.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(.shopPurple)
                }
            }
        }
    }
}

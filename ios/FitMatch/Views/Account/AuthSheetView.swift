import SwiftUI
import AuthenticationServices
import CryptoKit
import Security

// MARK: - Auth Sheet (Apple Sign In with SHA-256 Nonce + Email Login/Signup + Password Reset)

struct AuthSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var supabase = SupabaseManager.shared
    @ObservedObject private var wishlist = WishlistManager.shared
    @ObservedObject private var prefs = UserPreferencesManager.shared

    private enum AuthField: Hashable {
        case email
        case password
        case confirmPassword
    }

    @State private var isRegistering: Bool = false
    @State private var isResettingPassword: Bool = false
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var isConfirmPasswordVisible: Bool = false
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @State private var currentAppleNonce: String? = nil
    @State private var legalSheetType: AccountLegalType? = nil

    @FocusState private var focusedField: AuthField?

    private var canSubmit: Bool {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLoading || cleanEmail.isEmpty { return false }
        if isResettingPassword { return true }
        if password.isEmpty { return false }
        if isRegistering && confirmPassword.isEmpty { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    headerIconAndTitle

                    if !isResettingPassword {
                        appleSignInButton

                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.shopBorder)
                                .frame(height: 1)
                            Text("oppure con email")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.shopTextMuted)
                            Rectangle()
                                .fill(Color.shopBorder)
                                .frame(height: 1)
                        }

                        Picker("Modalità", selection: $isRegistering) {
                            Text("Accedi").tag(false)
                            Text("Registrati").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 4)
                        .onChange(of: isRegistering) { _ in
                            errorMessage = nil
                            successMessage = nil
                            confirmPassword = ""
                        }
                    }

                    if let err = errorMessage {
                        statusBanner(icon: "exclamationmark.triangle.fill", text: err, color: .shopRed)
                    }

                    if let success = successMessage {
                        statusBanner(icon: "checkmark.circle.fill", text: success, color: .shopGreen)
                    }

                    formFields

                    // Primary CTA
                    Button(action: {
                        focusedField = nil
                        Task { await handleAuthSubmit() }
                    }) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(primaryButtonTitle)
                                .font(.system(size: 15.5, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.shopPurple)
                        .clipShape(Capsule())
                        .shadow(color: Color.shopPurple.opacity(0.28), radius: 8, y: 4)
                    }
                    .buttonStyle(ShopCardPressStyle(scale: 0.98, pressedOpacity: 0.92))
                    .disabled(!canSubmit)
                    .opacity(canSubmit ? 1.0 : 0.55)
                    .padding(.top, 4)

                    if isResettingPassword {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isResettingPassword = false
                                errorMessage = nil
                                successMessage = nil
                            }
                        }) {
                            Text("Torna all'accesso")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.shopPurple)
                        }
                        .buttonStyle(.plain)
                    } else {
                        // Guest migration reassurance
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.shopGreen)
                            Text("I salvati, le taglie e gli store della sessione ospite verranno uniti al tuo account.")
                                .font(.system(size: 11.5))
                                .foregroundColor(.shopTextMuted)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 6)

                        if isRegistering {
                            legalConsentNotice
                        }
                    }
                }
                .padding(ShopLayout.screenPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.shopSurface.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .foregroundColor(.shopPurple)
                }
            }
            .sheet(item: $legalSheetType) { legal in
                AccountLegalSheetView(type: legal, storeCount: max(prefs.activeStores.count, 20))
            }
        }
    }

    private var navigationTitle: String {
        if isResettingPassword { return "Recupera password" }
        return isRegistering ? "Registrazione" : "Accedi"
    }

    private var primaryButtonTitle: String {
        if isResettingPassword { return "Invia link di recupero" }
        return isRegistering ? "Crea Account" : "Accedi"
    }

    private var headerIconAndTitle: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.shopPurpleLight)
                    .frame(width: 60, height: 60)
                Image(systemName: isResettingPassword ? "key.fill" : (isRegistering ? "person.badge.plus" : "lock.shield.fill"))
                    .font(.system(size: 25))
                    .foregroundColor(.shopPurple)
            }
            .padding(.top, 8)

            Text(
                isResettingPassword
                    ? "Recupera la tua password"
                    : (isRegistering ? "Crea il tuo Account" : "Bentornato su FitMatch")
            )
            .font(.system(size: 22, weight: .bold, design: .rounded))
            .foregroundColor(.shopDark)

            Text(
                isResettingPassword
                    ? "Inserisci l'email del tuo account: ti invieremo un link per reimpostare la password."
                    : (isRegistering
                        ? "Sincronizza salvati, taglie, brand e avvisi di prezzo su tutti i tuoi dispositivi."
                        : "Accedi per ritrovare i tuoi prodotti salvati, le collezioni e le preferenze.")
            )
            .font(.system(size: 13.5))
            .foregroundColor(.shopTextMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
        }
    }

    private var appleSignInButton: some View {
        SignInWithAppleButton(
            onRequest: { request in
                errorMessage = nil
                successMessage = nil
                let rawNonce = Self.generateRandomNonce()
                currentAppleNonce = rawNonce
                request.requestedScopes = [.fullName, .email]
                request.nonce = Self.sha256(rawNonce)
            },
            onCompletion: { result in
                switch result {
                case .success(let authorization):
                    guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                        errorMessage = "Credenziali Apple non valide."
                        return
                    }
                    if let fullName = appleIDCredential.fullName {
                        let name = [fullName.givenName, fullName.familyName]
                            .compactMap { $0 }
                            .joined(separator: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty {
                            prefs.preferences.userName = name
                        }
                    }
                    guard let tokenData = appleIDCredential.identityToken,
                          let idToken = String(data: tokenData, encoding: .utf8) else {
                        errorMessage = "Token Apple mancante. Riprova."
                        return
                    }
                    let resolvedEmail = appleIDCredential.email ?? SupabaseManager.extractEmailFromJWT(idToken)
                    let nonce = currentAppleNonce
                    isLoading = true
                    Task {
                        do {
                            try await supabase.signInWithApple(idToken: idToken, rawNonce: nonce, email: resolvedEmail)
                            await wishlist.syncWithDatabase(force: true)
                            await MainActor.run {
                                ShopHaptics.notification(.success)
                                isLoading = false
                                dismiss()
                            }
                        } catch {
                            await MainActor.run {
                                ShopHaptics.notification(.error)
                                isLoading = false
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                case .failure(let error):
                    let nsErr = error as NSError
                    if nsErr.domain == ASAuthorizationError.errorDomain && nsErr.code == ASAuthorizationError.canceled.rawValue {
                        return
                    }
                    errorMessage = "Accesso con Apple non disponibile (\(nsErr.localizedDescription))."
                }
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 50)
        .clipShape(Capsule())
    }

    private var formFields: some View {
        VStack(spacing: 14) {
            // Email Field
            VStack(alignment: .leading, spacing: 6) {
                Text("Email")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(.shopDark)

                HStack(spacing: 10) {
                    Image(systemName: "envelope")
                        .foregroundColor(.shopTextMuted)
                        .frame(width: 20)
                    TextField(
                        "",
                        text: $email,
                        prompt: Text(verbatim: "nome@esempio.it").foregroundColor(.shopTextMuted.opacity(0.65))
                    )
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(isResettingPassword ? .send : .next)
                    .focused($focusedField, equals: .email)
                    .onSubmit {
                        if isResettingPassword {
                            Task { await handleAuthSubmit() }
                        } else {
                            focusedField = .password
                        }
                    }
                }
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(focusedField == .email ? Color.shopPurple : Color.shopBorder, lineWidth: focusedField == .email ? 1.5 : 1)
                )
            }

            if !isResettingPassword {
                // Password Field
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Password")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.shopDark)
                        Spacer()
                        if !isRegistering {
                            Button("Password dimenticata?") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isResettingPassword = true
                                    errorMessage = nil
                                    successMessage = nil
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.shopPurple)
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "lock")
                            .foregroundColor(.shopTextMuted)
                            .frame(width: 20)
                        if isPasswordVisible {
                            TextField("Almeno 6 caratteri", text: $password)
                                .textContentType(isRegistering ? .newPassword : .password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .submitLabel(isRegistering ? .next : .go)
                                .focused($focusedField, equals: .password)
                                .onSubmit { handlePasswordSubmit() }
                        } else {
                            SecureField("Almeno 6 caratteri", text: $password)
                                .textContentType(isRegistering ? .newPassword : .password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .submitLabel(isRegistering ? .next : .go)
                                .focused($focusedField, equals: .password)
                                .onSubmit { handlePasswordSubmit() }
                        }
                        Button(action: { isPasswordVisible.toggle() }) {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundColor(.shopTextMuted)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(focusedField == .password ? Color.shopPurple : Color.shopBorder, lineWidth: focusedField == .password ? 1.5 : 1)
                    )
                }

                // Confirm Password (Registration only)
                if isRegistering {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Conferma Password")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundColor(.shopDark)

                        HStack(spacing: 10) {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.shopTextMuted)
                                .frame(width: 20)
                            if isConfirmPasswordVisible {
                                TextField("Ripeti la password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .submitLabel(.go)
                                    .focused($focusedField, equals: .confirmPassword)
                                    .onSubmit {
                                        Task { await handleAuthSubmit() }
                                    }
                            } else {
                                SecureField("Ripeti la password", text: $confirmPassword)
                                    .textContentType(.newPassword)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .submitLabel(.go)
                                    .focused($focusedField, equals: .confirmPassword)
                                    .onSubmit {
                                        Task { await handleAuthSubmit() }
                                    }
                            }
                            Button(action: { isConfirmPasswordVisible.toggle() }) {
                                Image(systemName: isConfirmPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundColor(.shopTextMuted)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(focusedField == .confirmPassword ? Color.shopPurple : Color.shopBorder, lineWidth: focusedField == .confirmPassword ? 1.5 : 1)
                        )
                    }
                }
            }
        }
    }

    private var legalConsentNotice: some View {
        VStack(spacing: 4) {
            Text("Creando un account accetti i nostri")
                .font(.system(size: 11.5))
                .foregroundColor(.shopTextMuted)
            HStack(spacing: 6) {
                Button("Termini e condizioni") { legalSheetType = .terms }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .buttonStyle(.plain)
                Text("e la")
                    .font(.system(size: 11.5))
                    .foregroundColor(.shopTextMuted)
                Button("Privacy Policy") { legalSheetType = .privacy }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.shopPurple)
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private func statusBanner(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handlePasswordSubmit() {
        if isRegistering {
            focusedField = .confirmPassword
        } else {
            Task { await handleAuthSubmit() }
        }
    }

    private func handleAuthSubmit() async {
        errorMessage = nil
        successMessage = nil
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleanEmail.contains("@") && cleanEmail.contains(".") else {
            errorMessage = "Inserisci un indirizzo email valido."
            return
        }

        if isResettingPassword {
            isLoading = true
            defer { isLoading = false }
            do {
                try await supabase.resetPassword(email: cleanEmail)
                ShopHaptics.notification(.success)
                successMessage = "Email di recupero inviata! Controlla la tua casella di posta."
            } catch {
                ShopHaptics.notification(.error)
                errorMessage = error.localizedDescription
            }
            return
        }

        guard password.count >= 6 else {
            errorMessage = "La password deve contenere almeno 6 caratteri."
            return
        }
        if isRegistering && password != confirmPassword {
            errorMessage = "Le due password non coincidono."
            return
        }

        isLoading = true
        defer { isLoading = false }

        if isRegistering {
            do {
                let res = try await supabase.signUp(email: cleanEmail, password: password)
                ShopHaptics.notification(.success)
                if supabase.isAuthenticated {
                    await wishlist.syncWithDatabase(force: true)
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    dismiss()
                } else {
                    successMessage = res.message
                }
            } catch {
                errorMessage = error.localizedDescription
                ShopHaptics.notification(.error)
            }
        } else {
            do {
                try await supabase.signIn(email: cleanEmail, password: password)
                ShopHaptics.notification(.success)
                await wishlist.syncWithDatabase(force: true)
                try? await Task.sleep(nanoseconds: 450_000_000)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                ShopHaptics.notification(.error)
            }
        }
    }

    // MARK: - Cryptographic Nonce Helpers for Sign in with Apple

    private static func generateRandomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        })
    }

    private static func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

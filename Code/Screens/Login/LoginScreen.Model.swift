//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import Foundation

extension LoginScreen {
    @Observable @MainActor
    final class Model {
        enum Stage: Equatable {
            case credentials
            /// The password was accepted; the service is waiting for a second factor.
            case twoFactor(TwoFactorType)
        }

        var login = ""
        var password = ""
        var code = ""

        private(set) var stage: Stage = .credentials
        private(set) var isBusy = false
        private(set) var errorMessage: String?

        @ObservationIgnored
        private let session: SessionStore

        init(session: SessionStore) {
            self.session = session
        }

        var canSubmit: Bool {
            guard !isBusy else { return false }

            return switch stage {
                case .credentials: !login.isEmpty && !password.isEmpty
                case .twoFactor: code.count >= 4
            }
        }

        var submitTitle: String {
            switch stage {
                case .credentials: String(localized: "Sign in")
                case .twoFactor: String(localized: "Confirm")
            }
        }

        func submit() async {
            guard canSubmit else { return }

            isBusy = true
            errorMessage = nil

            do {
                let sentCode = stage == .credentials ? nil : code
                let result = try await session.signIn(login: login, password: password, code: sentCode)

                if result.requiresTwoFactor {
                    stage = .twoFactor(result.twoFactorType ?? .code)
                }
            } catch let error as AuthorTodayError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = "Couldn’t sign in. Check your connection."
            }

            isBusy = false
        }

        /// Drops back to the password step, e.g. after a mistyped address.
        func restart() {
            stage = .credentials
            code = ""
            errorMessage = nil
        }
    }
}

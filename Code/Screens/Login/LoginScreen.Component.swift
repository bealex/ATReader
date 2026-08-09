//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import SwiftUI

enum LoginScreen {
    struct Component: View {
        @Environment(SessionStore.self)
        private var session

        @State
        private var model: Model?

        @FocusState
        private var focus: Field?

        private enum Field: Hashable {
            case login
            case password
            case code
        }

        var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    if let model {
                        form(model)
                    }
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if model == nil { model = Model(session: session) }
            }
        }

        private var header: some View {
            VStack(spacing: 10) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("ATReader")
                    .font(.largeTitle.bold())

                Text("Read your author.today library")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
        }

        @ViewBuilder
        private func form(_ model: Model) -> some View {
            @Bindable var model = model

            VStack(spacing: 16) {
                switch model.stage {
                    case .credentials:
                        credentialFields($model)
                    case let .twoFactor(type):
                        twoFactorFields($model, type: type)
                }

                if let message = model.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Sign-in error: \(message)")
                }

                Button(
                    action: { Task { await model.submit() } },
                    label: {
                        Group {
                            if model.isBusy {
                                ProgressView()
                            } else {
                                Text(model.submitTitle)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 28)
                    }
                )
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("login.submit")
                .accessibilityLabel(model.submitTitle)
                .accessibilityHint("Submits your sign-in details")

                if case .twoFactor = model.stage {
                    Button("Use a different account", action: model.restart)
                        .font(.footnote)
                        .accessibilityHint("Go back to the username and password step")
                }
            }
            .padding(20)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
        }

        @ViewBuilder
        private func credentialFields(_ model: Bindable<Model>) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("Username or email")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("mail@example.com", text: model.login)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .login)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("login.field")
                    .accessibilityLabel("Username or email address")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Password")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SecureField("Password", text: model.password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit { Task { await model.wrappedValue.submit() } }
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("login.password")
                    .accessibilityLabel("Password")
            }
        }

        @ViewBuilder
        private func twoFactorFields(_ model: Bindable<Model>, type: TwoFactorType) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(type.prompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Verification code", text: model.code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .code)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("login.code")
                    .accessibilityLabel("Verification code")
                    .accessibilityHint("Enter the code you received")
            }
            .onAppear { focus = .code }
        }
    }
}

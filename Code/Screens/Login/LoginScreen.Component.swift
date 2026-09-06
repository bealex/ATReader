//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import AuthorToday
import DesignSystem
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
                VStack(spacing: Design.Space.huge) {
                    header

                    if let model {
                        form(model)
                    }
                }
                .padding(Design.Space.huge)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(Design.Surface.screen)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                if model == nil { model = Model(session: session) }
            }
        }

        private var header: some View {
            VStack(spacing: Design.Space.medium) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("ATReader")
                    .font(Design.Style.screenTitle)

                Text("Read your author.today library")
                    .font(Design.Style.label)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
        }

        @ViewBuilder
        private func form(_ model: Model) -> some View {
            @Bindable var model = model

            VStack(spacing: Design.Space.extraLarge) {
                switch model.stage {
                    case .credentials:
                        credentialFields($model)
                    case let .twoFactor(type):
                        twoFactorFields($model, type: type)
                }

                if let message = model.errorMessage {
                    Text(message)
                        .font(Design.Style.caption)
                        .foregroundStyle(Design.Palette.alert)
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
                        .actionLabel()
                    }
                )
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("login.submit")
                .accessibilityLabel(model.submitTitle)
                .accessibilityHint("Submits your sign-in details")

                if case .twoFactor = model.stage {
                    Button("Use a different account", action: model.restart)
                        .font(Design.Style.caption)
                        .accessibilityHint("Go back to the username and password step")
                }
            }
            .padding(Design.Space.extraLarge)
            .background(Design.Surface.card, in: .rect(cornerRadius: Design.Radius.large))
        }

        @ViewBuilder
        private func credentialFields(_ model: Bindable<Model>) -> some View {
            VStack(alignment: .leading, spacing: Design.Space.small) {
                Text("Username or email")
                    .font(Design.Style.caption)
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

            VStack(alignment: .leading, spacing: Design.Space.small) {
                Text("Password")
                    .font(Design.Style.caption)
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
            VStack(alignment: .leading, spacing: Design.Space.small) {
                Text(type.prompt)
                    .font(Design.Style.caption)
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

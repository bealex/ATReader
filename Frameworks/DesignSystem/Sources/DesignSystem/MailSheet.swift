//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

#if canImport(MessageUI)

    import MessageUI
    import SwiftUI
    import UniformTypeIdentifiers

    /// A letter ready to send, with one file attached.
    public struct MailDraft: Identifiable {
        public let recipient: String
        public let subject: String
        public let body: String
        public let attachment: URL

        public init(recipient: String, subject: String, body: String, attachment: URL) {
            self.recipient = recipient
            self.subject = subject
            self.body = body
            self.attachment = attachment
        }

        public var id: String { attachment.path }

        /// True where the device has a mail account to send from.
        @MainActor
        public static var canSend: Bool { MFMailComposeViewController.canSendMail() }
    }

    /// The system's mail composer, filled in from a draft.
    public struct MailSheet: UIViewControllerRepresentable {
        public let draft: MailDraft

        public init(draft: MailDraft) {
            self.draft = draft
        }

        public func makeUIViewController(context: Context) -> MFMailComposeViewController {
            let composer = MFMailComposeViewController()
            let type = UTType(filenameExtension: draft.attachment.pathExtension) ?? .data

            context.coordinator.dismiss = context.environment.dismiss
            composer.mailComposeDelegate = context.coordinator
            composer.setToRecipients([ draft.recipient ])
            composer.setSubject(draft.subject)
            composer.setMessageBody(draft.body, isHTML: false)

            if let data = try? Data(contentsOf: draft.attachment) {
                composer.addAttachmentData(
                    data,
                    mimeType: type.preferredMIMEType ?? "application/octet-stream",
                    fileName: draft.attachment.lastPathComponent
                )
            }

            return composer
        }

        public func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

        public func makeCoordinator() -> Coordinator { Coordinator() }

        @MainActor
        public final class Coordinator: NSObject, @MainActor MFMailComposeViewControllerDelegate {
            var dismiss: DismissAction?

            public func mailComposeController(
                _ controller: MFMailComposeViewController,
                didFinishWith result: MFMailComposeResult,
                error: (any Error)?
            ) {
                dismiss?()
            }
        }
    }
#endif

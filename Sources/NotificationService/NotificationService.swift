@preconcurrency import Intents
import Foundation
@preconcurrency import UserNotifications
import UIKit

private final class NotificationDeliveryState: @unchecked Sendable {
    private let lock = NSLock()
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNNotificationContent?
    private var didDeliver = false

    func prepare(
        content: UNNotificationContent,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        lock.lock()
        self.contentHandler = contentHandler
        bestAttemptContent = content
        didDeliver = false
        lock.unlock()
    }

    func updateBestAttempt(_ content: UNNotificationContent) {
        lock.lock()
        bestAttemptContent = content
        lock.unlock()
    }

    func deliver(_ content: UNNotificationContent) {
        let handler = takeHandlerForDelivery(content: content)
        handler?(content)
    }

    func deliverBestAttempt() {
        let delivery: (((UNNotificationContent) -> Void), UNNotificationContent)?

        lock.lock()
        if !didDeliver,
           let contentHandler,
           let bestAttemptContent {
            didDeliver = true
            delivery = (contentHandler, bestAttemptContent)
            self.contentHandler = nil
        } else {
            delivery = nil
        }
        lock.unlock()

        if let delivery {
            delivery.0(delivery.1)
        }
    }

    private func takeHandlerForDelivery(
        content: UNNotificationContent
    ) -> ((UNNotificationContent) -> Void)? {
        lock.lock()
        defer { lock.unlock() }

        guard !didDeliver else { return nil }
        didDeliver = true
        bestAttemptContent = content
        defer { contentHandler = nil }
        return contentHandler
    }
}

private final class CommunicationNotificationUpdate: @unchecked Sendable {
    private let content: UNMutableNotificationContent
    private let intent: INSendMessageIntent
    private let deliveryState: NotificationDeliveryState

    init(
        content: UNMutableNotificationContent,
        intent: INSendMessageIntent,
        deliveryState: NotificationDeliveryState
    ) {
        self.content = content
        self.intent = intent
        self.deliveryState = deliveryState
    }

    func finish() {
        do {
            let updated = try content.updating(from: intent)
            guard let resolved = updated.mutableCopy() as? UNMutableNotificationContent else {
                deliveryState.deliver(updated)
                return
            }
            resolved.title = content.title
            resolved.subtitle = content.subtitle
            resolved.body = content.body
            resolved.attachments = content.attachments
            deliveryState.updateBestAttempt(resolved)
            deliveryState.deliver(resolved)
        } catch {
            deliveryState.deliver(content)
        }
    }
}

private final class CommunicationNotificationRequest: @unchecked Sendable {
    private let content: UNMutableNotificationContent
    private let deliveryState: NotificationDeliveryState
    private let senderID: String
    private let senderName: String
    private let circleID: String
    private let circleName: String

    init?(
        content: UNMutableNotificationContent,
        deliveryState: NotificationDeliveryState
    ) {
        guard let senderID = content.userInfo["sender_id"] as? String,
              let senderName = content.userInfo["sender_name"] as? String,
              let circleID = content.userInfo["circle_id"] as? String,
              let circleName = content.userInfo["circle_name"] as? String else {
            return nil
        }
        self.content = content
        self.deliveryState = deliveryState
        self.senderID = senderID
        self.senderName = senderName
        self.circleID = circleID
        self.circleName = circleName
    }

    func start() {
        guard let value = content.userInfo["rich_media_url"] as? String,
              let remoteURL = URL(string: value) else {
            finish(mediaURL: nil)
            return
        }
        URLSession.shared.downloadTask(with: remoteURL) { [self] temporaryURL, _, _ in
            finish(mediaURL: temporaryURL.flatMap { persistDownloadedMedia($0, sourceURL: remoteURL) })
        }.resume()
    }

    private func persistDownloadedMedia(_ sourceURL: URL, sourceURL remoteURL: URL) -> URL? {
        let pathExtension = remoteURL.pathExtension.isEmpty ? "jpg" : remoteURL.pathExtension
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("notification-\(UUID().uuidString)")
            .appendingPathExtension(pathExtension)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            return nil
        }
    }

    private func finish(mediaURL: URL?) {
        if let mediaURL {
            if let attachment = try? UNNotificationAttachment(
                identifier: "circle-activity-media",
                url: mediaURL
            ) {
                content.attachments.insert(attachment, at: 0)
            }
        }
        deliveryState.updateBestAttempt(content)

        let logoName = NotificationBrandPreference.logoResourceName(
            prefersDarkAppearance: UITraitCollection.current.userInterfaceStyle == .dark
        )
        let logoURL = Bundle.main.url(forResource: logoName, withExtension: "png")
            ?? Bundle.main.url(forResource: "NotificationLogo", withExtension: "png")
        let sender = INPerson(
            personHandle: INPersonHandle(value: senderID, type: .unknown),
            nameComponents: nil,
            displayName: senderName,
            image: logoURL.flatMap(INImage.init(url:)),
            contactIdentifier: nil,
            customIdentifier: senderID,
            isMe: false,
            suggestionType: .instantMessageAddress
        )
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: INSpeakableString(spokenPhrase: circleName),
            conversationIdentifier: circleID,
            serviceName: "manna circle",
            sender: sender,
            attachments: nil
        )
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = INInteractionDirection.incoming
        let update = CommunicationNotificationUpdate(
            content: content,
            intent: intent,
            deliveryState: deliveryState
        )
        interaction.donate { _ in update.finish() }
    }
}

final class NotificationService: UNNotificationServiceExtension {
    private let deliveryState = NotificationDeliveryState()

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        deliveryState.prepare(content: content, contentHandler: contentHandler)

        if content.userInfo["notification_kind"] as? String != nil {
            deliverCommunicationNotification(content)
            return
        }

        if let logoURL = Bundle.main.url(forResource: "NotificationLogo", withExtension: "png"),
           let attachment = try? UNNotificationAttachment(
               identifier: "manna-circle-logo",
               url: logoURL
           ) {
            content.attachments.insert(attachment, at: 0)
        }

        deliveryState.deliver(content)
    }

    private func deliverCommunicationNotification(
        _ content: UNMutableNotificationContent
    ) {
        guard let request = CommunicationNotificationRequest(
            content: content,
            deliveryState: deliveryState
        ) else {
            deliveryState.deliver(content)
            return
        }
        request.start()
    }

    override func serviceExtensionTimeWillExpire() {
        deliveryState.deliverBestAttempt()
    }
}

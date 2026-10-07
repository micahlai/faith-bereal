@preconcurrency import Intents
import Foundation
@preconcurrency import UserNotifications

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
            deliveryState.updateBestAttempt(updated)
            deliveryState.deliver(updated)
        } catch {
            deliveryState.deliver(content)
        }
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
        guard let senderID = content.userInfo["sender_id"] as? String,
              let senderName = content.userInfo["sender_name"] as? String,
              let circleID = content.userInfo["circle_id"] as? String,
              let circleName = content.userInfo["circle_name"] as? String else {
            deliveryState.deliver(content)
            return
        }

        let senderImage = (content.userInfo["sender_avatar_url"] as? String)
            .flatMap(URL.init(string:))
            .flatMap(INImage.init(url:))
        let sender = INPerson(
            personHandle: INPersonHandle(value: senderID, type: .unknown),
            nameComponents: nil,
            displayName: senderName,
            image: senderImage,
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
        if let circleImage = (content.userInfo["circle_photo_url"] as? String)
            .flatMap(URL.init(string:))
            .flatMap(INImage.init(url:)) {
            intent.setImage(circleImage, forParameterNamed: \.speakableGroupName)
        }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        let update = CommunicationNotificationUpdate(
            content: content,
            intent: intent,
            deliveryState: deliveryState
        )
        interaction.donate { _ in
            update.finish()
        }
    }

    override func serviceExtensionTimeWillExpire() {
        deliveryState.deliverBestAttempt()
    }
}

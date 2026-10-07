import Intents
import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler

        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttemptContent = content

        if content.userInfo["notification_kind"] as? String != nil {
            deliverCommunicationNotification(content, contentHandler: contentHandler)
            return
        }

        if let logoURL = Bundle.main.url(forResource: "NotificationLogo", withExtension: "png"),
           let attachment = try? UNNotificationAttachment(
               identifier: "manna-circle-logo",
               url: logoURL
           ) {
            content.attachments.insert(attachment, at: 0)
        }

        contentHandler(content)
    }

    private func deliverCommunicationNotification(
        _ content: UNMutableNotificationContent,
        contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let senderID = content.userInfo["sender_id"] as? String,
              let senderName = content.userInfo["sender_name"] as? String,
              let circleID = content.userInfo["circle_id"] as? String,
              let circleName = content.userInfo["circle_name"] as? String else {
            contentHandler(content)
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
        interaction.donate { [weak self] _ in
            guard let self else { return }
            do {
                let updated = try content.updating(from: intent)
                self.bestAttemptContent = updated.mutableCopy() as? UNMutableNotificationContent
                contentHandler(updated)
            } catch {
                contentHandler(content)
            }
        }
    }

    override func serviceExtensionTimeWillExpire() {
        guard let contentHandler, let bestAttemptContent else { return }
        contentHandler(bestAttemptContent)
    }
}

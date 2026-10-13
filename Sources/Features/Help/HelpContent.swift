import Foundation

// Customer-facing feature guide. Update this catalog whenever behavior changes.
enum HelpTopic: String, CaseIterable, Identifiable {
    case sharing, evening, circles, timeline, responses, saving, scripture, notifications, personalization, accessibility

    var id: Self { self }
    var title: String {
        switch self {
        case .sharing: "Sharing a blessing"
        case .evening: "End-of-day blessings"
        case .circles: "Your circles"
        case .timeline: "Today & Timeline"
        case .responses: "Responses"
        case .saving: "Saving & media expiry"
        case .scripture: "Bible verses"
        case .notifications: "Notifications & widgets"
        case .personalization: "Profile & appearance"
        case .accessibility: "Accessibility"
        }
    }

    var icon: String {
        switch self {
        case .sharing: "sun.max"
        case .evening: "moon.stars"
        case .circles: "person.3"
        case .timeline: "clock"
        case .responses: "bubble.left.and.bubble.right"
        case .saving: "bookmark"
        case .scripture: "book.closed"
        case .notifications: "bell.badge"
        case .personalization: "person.crop.circle"
        case .accessibility: "accessibility"
        }
    }

    var summary: String {
        switch self {
        case .sharing: "A shared moment. Your own words."
        case .evening: "One more reflection at the day's end."
        case .circles: "Join, create, switch, and lead."
        case .timeline: "Today's stories and your circle's history."
        case .responses: "Keep the conversation going."
        case .saving: "Keep a private copy before audio/video expires."
        case .scripture: "Tag a passage; read it in your chosen version."
        case .notifications: "Stay connected, on your terms."
        case .personalization: "Make manna feel like yours."
        case .accessibility: "Read, listen, and navigate your way."
        }
    }

    var steps: [HelpStep] {
        switch self {
        case .sharing: [
            .init("iphone", "Stay awake while recording", "Your phone stays awake during voice recording for blessings and responses. Pausing, closing the recorder, or leaving manna restores normal screen sleep. Recording does not continue in the background."),
            .init("person.badge.plus", "Your first day", "If today's notification has already started, your first day blessing belongs to today and you may enter until the circle's day ends. Before today's notification, your welcome blessing belongs to yesterday and entry closes when today's notification starts. Opening in time lets you finish later without changing its Timeline date."),
            .init("waveform", "Pause and continue", "Voice blessings and voice responses can be recorded in segments: pause, listen, then Continue recording to add more. Your existing words and audio are kept and combined before sending. Editing the transcript does not discard the audio. Start over on a blessing clears its recording. Wait for combining to finish before sending."),
            .init("bell", "Wait for your circle", "Your circle gets one random daily invitation within the time range and time zone its leader chooses. Everyone in that circle gets the same start time."),
            .init("clock.arrow.circlepath", "When the invitation starts", "The server opens sharing when it starts your circle's notification, not just when its planned time passes. A short delivery delay does not end your welcome blessing early."),
            .init("door.left.hand.open", "Open before the deadline", "The timer controls when you can enter the composer, not when you must finish. Once inside, you can send afterward—even past midnight—and the blessing stays on the original day. See Your first day for the welcome blessing's day and entry cutoff."),
            .init("clock.badge.xmark", "Past days stay closed", "Late sharing does not reopen a past day. A leftover Live Activity cannot override the circle's day boundary. If you already opened the composer while entry was allowed, you may still finish that blessing later."),
            .init("mic", "Choose your format", "Type, record your voice, or take a video. Blessing text and voice/video transcripts allow up to 1,200 characters, including when editing. The counter includes the parts of combined emoji and accented characters. Responses still allow 600 characters. Text and voice can also include a photo. Check microphone, speech, and camera access in Settings if recording is unavailable."),
            .init("arrow.triangle.2.circlepath", "Edit or reuse", "You can edit your own text/transcript and Bible tag for 10 minutes after sending. A reuse option appears when a blessing you sent to another circle is still within this circle's reuse window, measured from when you sent it. Reuse keeps its original format, text/transcript, Bible tag, and attached audio, photo, or video. Responses are not copied. People in the receiving circle unlock it by sharing there."),
            .init("hand.wave", "Give a gentle nudge", "After sharing for a prompt, Today lets you nudge a member who hasn't shared that same daily or end-of-day blessing while entry is open, or while daily late sharing is available. Each person can receive only one nudge per prompt across the circle. A nudge never reveals your blessing. Their circle activity notification switch still applies. Queued nudges are skipped if they share or the window closes before delivery; local demo mode does not send a real notification."),
        ]
        case .evening: [
            .init("moon.stars", "A separate invitation", "The circle leader chooses the end-of-day time, default 10 p.m. in the circle's time zone. It cannot be earlier than the end of the random-time range."),
            .init("plus", "Share from Today", "An end-of-day button appears above the feed, without a countdown or Live Activity. Entry closes after seven hours or when the next day's random blessing starts, whichever comes first."),
            .init("lock.open", "Unlock evening stories", "You must send an end-of-day blessing to see others' evening blessings. Sending the random daily blessing does not unlock them. The two types share the feed, but have separate sharing gates."),
        ]
        case .circles: [
            .init("link", "Join people you know", "Enter a circle's code or open its join link. Installed apps open the link directly. The circle page lets you share that link with friends. App updates and relaunches do not change the code; only a leader's Regenerate action changes it. For an older circle whose code is unavailable, use a saved join link to recover it or ask the leader to regenerate once."),
            .init("slider.horizontal.3", "Create with intention", "The guided setup explains each setting before you create anything. Defaults are noon–10 p.m., a 10-minute entry window, late sharing on, and an end-of-day reflection at 10 p.m."),
            .init("arrow.left.arrow.right", "Switch circles", "Use the circle-name menu at the top. Blessings belong to the circle you send them to; switching changes Today, Timeline, and circle settings."),
            .init("person.badge.key", "Lead or leave", "Leaders can rename the circle, change its photo and schedule, allow late sharing, regenerate codes, remove members, or transfer leadership. Circle settings also lets you leave. If a leader leaves, leadership passes to a remaining member; an empty circle is deleted."),
        ]
        case .timeline: [
            .init("flame", "A streak for each circle", "Share either the regular or evening blessing to count one circle-local day, even if late. Two blessings on one day count once; sharing in another circle doesn't add to this streak. Today's unshared day does not break yesterday's streak until that day has passed. Welcome blessings are separate and do not count for today's regular/evening streak. The fire shows consecutive days; on-time sharing earns a checkmarked badge without penalizing late sharing's streak."),
            .init("calendar", "Load older days", "Timeline starts with the most recent 14 days. Use Load older days at the bottom to add the next page without losing the days already shown. A refresh updates recent days and keeps your loaded history. Switching circles starts with that circle's recent page."),
            .init("plus.magnifyingglass", "Make Timeline fit", "Threads starts with compact cards. Pinch to resize the member columns, or use Smaller, Larger, and Reset size in the Timeline layout menu. Your size is remembered on this device; text still follows your system text size. List remains an accessible alternative."),
            .init("arrow.down", "Scroll through history", "Timeline draws cards as they come into view instead of building the whole history at once. Photos, recordings, and replies load when needed. On a slow connection, let a card finish loading before opening its media."),
            .init("bell", "When the circle was notified", "The left date strip shows the actual daily and evening notification times in your circle's time zone. Your card shows when you sent your blessing; these are different times. A welcome blessing does not add yesterday's notification time to today's strip."),
            .init("list.bullet", "A chronological List", "Switch Timeline to List to see actual blessings and joining events, newest first by when they happened. List does not include missed days, locked placeholders, or days still waiting to start. Threads still shows each person's day-by-day lane."),
            .init("hand.wave", "Your welcome blessing", "An early welcome blessing appears on the day you actually sent it, above Joined circle, labeled Welcome blessing. This changes only its display: it remains separate from that day's regular blessing, which you can still share when the notification starts."),
            .init("sun.max", "Today is a shared feed", "After you share, visible blessings fill Today in newest-first order, with photos, audio/video, Bible verses, and responses. Peer blessings for a prompt stay locked until you share for that prompt."),
            .init("point.3.connected.trianglepath.dotted", "Follow each person's story", "Timeline has a lane per person. Scroll vertically for days and horizontally for people; the date strip and profile row stay in place. Each lane ends at Joined circle—no missed days are added before membership."),
            .init("hand.tap", "Open the whole blessing", "Tap a card for its full content. Preview text is limited to 15 lines; Bible previews to five lines, with an expand option. Evening blessings sit above the random blessing in the same day row."),
            .init("lock.open", "History remains visible", "Past history is readable without sharing today. Unstarted prompts are hidden from Timeline; Today waits until the invitation has started. You can still share means entry is available, including the first-day exception. Future days are not shown as missed. Missed, locked, late, and still-open states explain what happened without relying on color alone."),
        ]
        case .responses: [
            .init("text.bubble", "Reply simply", "Use the small response box, microphone, and send button on Today. A current-day blessing opened from Timeline can also accept a response. Historical blessings are read-only."),
            .init("waveform", "Text or voice", "Voice responses include both recorded audio and a transcript. You can listen before sending. Responses do not support photos or video."),
            .init("person.crop.circle", "See who replied", "Timeline cards show responder profile icons. Response rows show the person's profile photo beside their name. Open a blessing to read responses or listen to saved/available audio."),
        ]
        case .saving: [
            .init("questionmark.circle", "Should I turn automatic saving on?", "Audio and video are deleted from the server after 30 days. Automatically save locally keeps private copies while manna is open so you can enjoy them later. If this is off, you can still choose individual blessings and tap Save. Text, Bible references, and photos remain in circle history."),
            .init("clock", "30 days for hosted media", "Blessing audio/video and response audio expire 30 days after each was sent. Text, transcripts, Bible references, and photos stay in circle history. A warning above Timeline cards appears during the final two days."),
            .init("bookmark", "Save the blessing", "Save blessing downloads a private copy of its text, Bible reference, photo/audio/video, and the responses available now. Wait until it is marked Saved. Future responses aren't added automatically. Saving does not prevent server deletion for other people."),
            .init("arrow.down.circle", "Save automatically if you want", "Choose Automatically save locally during setup or in User settings. While manna is open, visible blessings from all your circles download privately, and automatic copies refresh as new responses become available. Locked posts never unlock through saving. Open the app regularly; it cannot guarantee downloads while closed. Unsaving an individual blessing stops it being automatically saved again."),
            .init("checklist", "Turning automatic saving off", "Keep all, Keep only my blessings, Keep none, or Choose from a list. Kept copies become ordinary manual saves; existing manual saves are never removed. A warning confirms permanent removal of expired media. This preference and your copies belong to this account on this device."),
            .init("iphone", "Only this account, on this device", "Open saved media from the same Timeline card after expiry. Copies do not sync to another device or another person and are lost if you uninstall manna or lose the device. Save photo/video to Photos is a separate export option."),
            .init("bookmark.slash", "Unsave carefully", "Unsave removes your device's copy. If captured media has already expired on the server, manna warns you first: removing the last local copy is permanent. Saving after expiry preserves only what is still available."),
        ]
        case .scripture: [
            .init("book.closed", "Add a verse if you want", "Choose a book and chapter, then tap or drag across the verse grid to select a range. Preview the passage before sending. A Bible tag is always optional."),
            .init("globe", "Read in your version", "Choose a Bible version in User settings. Versions are grouped by language. Everyone's tagged references are displayed in your selection; the server stores the reference, not a translation of the text."),
            .init("arrow.up.left.and.arrow.down.right", "Read the full passage", "Passages include verse numbers. Longer passages show their first five lines with an expand button for the full text. Loading requires an internet connection."),
        ]
        case .notifications: [
            .init("bell.badge", "Choose circle alerts", "In User settings, each circle has separate switches for other members' blessings/followed responses/nudges and the end-of-day reminder. Response alerts go to the blessing author and people who previously responded, not the new responder. Nudges remind you to share without revealing anyone's blessing."),
            .init("person.crop.circle", "Recognize the sender", "Blessing and response alerts show the sender's full profile photo on the left. If their photo is missing or cannot load, the manna logo is the fallback. iOS adds its own small app-icon badge. Unlocked blessing photos or video previews may appear on the right; responses have no right image."),
            .init("timer", "Live Activities", "The daily invitation can appear on your Lock Screen and Dynamic Island. It updates after you submit and disappears after a three-minute grace period. Late-enabled sharing stays available until you submit or a newer prompt replaces it."),
            .init("square.grid.2x2", "Add a Home Screen widget", "Touch and hold the Home Screen, choose Edit → Add Widget, search for manna circle, and choose a size. During sharing time, tap it to open Today. Otherwise it rotates visible blessings; tap one to open it."),
            .init("arrow.clockwise", "Refresh a widget", "Open manna after signing in or joining a circle to refresh its shared widget data. After restarting your phone, unlock it once. Widgets prepare known sharing times in advance, but iOS controls refresh timing; they cannot fetch new blessings while the app has not refreshed."),
            .init("gearshape", "Control the experience", "Choose the widget refresh interval in User settings, default 30 minutes. iOS controls exact refresh and delivery timing. If alerts or Live Activities are missing, check their permissions in iPhone Settings."),
        ]
        case .personalization: [
            .init("person.crop.circle", "Start with your profile", "Setup offers a Your profile step to review your Apple-provided name and choose an optional square-cropped photo. Continue keeps your current profile. You can edit it later in User settings."),
            .init("person.crop.circle.badge.checkmark", "Your account", "The sign-in screen shows the manna logo. To sign out, open User settings and scroll to Sign out; it is not in the app menu or Circle page."),
            .init("person.crop.circle", "Your profile", "Use User settings to change your name and profile photo. Profile and circle photos use a circular preview; pinch and drag together to crop, or use Adjust photo to zoom and move without gestures. VoiceOver also offers crop actions. The uploaded image is square."),
            .init("circle.lefthalf.filled", "Light, dark, or automatic", "Choose appearance in User settings. Automatic follows your device. Colors keep text readable in both appearances. Choose your app icon separately; the logo artwork is also used in manna's branded surfaces."),
            .init("line.3.horizontal", "Find your way back", "The hamburger menu keeps Help, About, User settings, and circle management within reach. You can revisit this guide whenever you need it."),
        ]
        case .accessibility: [
            .init("textformat.size", "Larger text & readable colors", "manna follows your iPhone's text size, Reduce Motion, and contrast settings. Choose Light, Dark, or Automatic in User settings. Sharing states use words and symbols, not just color."),
            .init("list.bullet", "An easier Timeline", "Open Timeline layout at the top of Timeline and choose List for one vertical stream of dates, people, and blessings. It is selected automatically for VoiceOver and accessibility text sizes. Threads remains available if you prefer member lanes."),
            .init("hand.tap", "Controls without gestures", "Use the start and end verse controls instead of dragging the grid. In the photo crop editor, Adjust photo offers zoom, movement, and reset. VoiceOver offers these crop actions too. Named buttons work with Voice Control."),
            .init("text.bubble", "Read recordings", "Voice and video blessings, and voice responses, show their transcripts as readable text. Authors can correct transcripts before sharing. Transcripts may contain mistakes; timed video captions and narrated descriptions of visual content are not yet available."),
        ]
        }
    }
}

struct HelpStep {
    let icon: String
    let title: String
    let body: String

    init(_ icon: String, _ title: String, _ body: String) {
        self.icon = icon; self.title = title; self.body = body
    }
}

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
            .init("pencil.and.outline", "Continue a draft", "Your composer checkpoints text, Bible tags, photos, video, and voice segments privately on this device as you work. On Today, Share a blessing changes to Continue when a saved draft for that daily blessing can still be entered. The end-of-day share button does the same for its own draft. Tap that same button to restore your unsent changes; there is no separate draft button. Drafts survive a failed send or relaunch, but the last moments before a crash may not be saved. They are removed after sending or at the next circle-local midnight after you began. A draft never extends the entry deadline: if late sharing is off and the window closed, you cannot reopen it. A composer opened in time may still finish afterward. Copies are account- and circle-specific and do not sync."),
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
            .init("link", "Join people you know", "Enter a circle's code or open its join link. Installed apps open the link directly. The circle page lets you share that link with friends. App updates and relaunches do not change the code; only an authorized Regenerate action changes it. For an older circle whose code is unavailable, use a saved join link to recover it or ask the leader to regenerate once."),
            .init("slider.horizontal.3", "Create with intention", "The guided setup explains each setting before you create anything. Defaults are noon–10 p.m., a 10-minute entry window, late sharing on, and an end-of-day reflection at 10 p.m."),
            .init("arrow.left.arrow.right", "Switch circles", "Use the circle-name menu at the top. Blessings belong to the circle you send them to; switching changes Today, Timeline, and circle settings. The selected circle's name and people appear while blessings load. A loading message stays above the page, and you can still move between tabs. Wait for the selected circle to finish loading before sharing, opening circle settings, or sharing a join link. If a switch fails, your previous circle returns; select the other circle again to try again. Retry refreshes the circle currently shown. At startup, saved names and people may appear while blessings load; Retry reloads them if the connection fails. Circle details, members, streaks, and profile/circle photos stay on this device for up to seven days; signing out clears them. Basic circle details are saved before blessings finish loading, so a slow or failed first page can still leave them ready for the next launch. Blessings still need a fresh connection. Old blessings from another circle are never shown under the new circle's name."),
            .init("person.badge.key", "Lead or leave", "Leaders can turn Anyone can make circle changes on or off. It starts off. When on, current members can change the circle name, photo, schedule, late-sharing and reuse settings, regenerate invite codes, force a notification, and remove another nonleader member. The permission switch and Transfer circle ownership stay leader-only. Members cannot remove the leader; use Leave circle to leave yourself. Circle settings also lets you leave. If a leader leaves, leadership passes to a remaining member; an empty circle is deleted."),
        ]
        case .timeline: [
            .init("flame", "A streak for each circle", "Your overall streak counts consecutive circle-local days when you sent either the random or evening blessing, even if late. Two blessings on one day count once; sharing in another circle doesn't add to this streak. Your on time streak counts only random blessings entered before their deadline. Evening blessings never earn an on time day. An evening-only day keeps the overall streak going, but the on time streak resets when that day's random window closes without an on time random blessing. A late random entry breaks the blue run even when the overall streak continues. Counts update after posting or when the relevant window closes: random for on time, the final evening opportunity for overall. An unfinished window preserves the previous run, including an evening window continuing after midnight. Welcome blessings do not count. One flame pill in Today and Timeline always shows the overall count: blue only when both streak counts are equal, otherwise red. It sits at the top-right of the profile photo without moving the name. The Circle People panel shows both positive counts on the right, red for overall and blue for on time. It shows only red when on time is zero, and no flame when both are zero. For example, five consecutive sharing days with the last three random blessings on time means 5 overall and 3 on time. Tap a flame to open a small animated popup showing both counts, including zero: red shows days in a row, blue shows on time days in a row. Entering before the random deadline counts as timely even if you finish sending afterward; sending afterward does not lose it. There is no verification badge. A card's Late label describes when it was sent, not when you entered. Older posts without entry records use their on-time sending status."),
            .init("calendar", "Load older days", "Timeline starts with the most recent 14 days. Use Load older days at the bottom to add the next page without losing the days already shown. A refresh updates recent days and keeps your loaded history. Switching circles starts with that circle's recent page. Changing accounts or the circle's time zone resets paging so histories do not get mixed."),
            .init("plus.magnifyingglass", "Make Timeline fit", "Threads starts with compact cards. Pinch to resize the member columns, or use Smaller, Larger, and Reset size in the Timeline layout menu. Your size is remembered on this device; text still follows your system text size. List remains an accessible alternative."),
            .init("arrow.down", "Scroll through history", "Timeline draws cards as they come into view instead of building the whole history at once. Photos, recordings, and replies load when needed. On a slow connection, let a card finish loading before opening its media."),
            .init("play.circle", "If a recording cannot load", "Refresh Today or Timeline to get an updated recording link, then open the recording and try again. A missing or unreadable recording may still be unavailable. When Share diagnostic data is on, failed recording downloads and playback add a download status or short audio error code to help investigate. Recording contents and links are never included in those reports."),
            .init("bell", "When the circle was notified", "The left date strip shows only the actual random blessing notification time in your circle's time zone. The evening notification time is hidden. Your card still shows when you sent your blessing. A welcome blessing does not add yesterday's notification time to today's strip."),
            .init("list.bullet", "A chronological List", "Timeline opens in List, showing actual blessings and joining events, newest first by when they happened. Use the wide Timeline layout button in the top bar to choose List or Threads. In List, the person filter starts at All; choose a person to see only their events. The picker shows profile photos, with initials when no photo is available; the chosen person’s photo stays beside their name. The filter applies only to List, and Threads always shows everyone. Returning to List keeps your choice; changing circles resets it to All. List does not include missed days, locked placeholders, or days still waiting to start. Threads still shows each person's day-by-day lane."),
            .init("hand.wave", "Your welcome blessing", "An early welcome blessing appears on the day you actually sent it, above Joined circle, labeled Welcome blessing. This changes only its display: it remains separate from that day's regular blessing, which you can still share when the notification starts."),
            .init("sun.max", "Today is a shared feed", "After you share, visible blessings fill Today in newest-first order, with photos, audio/video, Bible verses, and responses. Today scrolls vertically and stays fixed side to side. Peer blessings for a prompt stay locked until you share for that prompt."),
            .init("point.3.connected.trianglepath.dotted", "Follow each person's story", "Timeline has a lane per person. Scroll vertically for days and horizontally for people; the date strip and profile row stay in place. Each lane ends at Joined circle—no missed days are added before membership."),
            .init("hand.tap", "Open the whole blessing", "Tap a card for its full content. Preview text is limited to 15 lines; Bible previews to five lines, with an expand option. Evening blessings sit above the random blessing in the same day row."),
            .init("photo", "Look closer at photos", "Tap an attached blessing photo to enlarge it. Profile and circle photos do not open the viewer. Pinch to zoom, drag to move around, or double-tap to zoom and reset. Zoom in, Zoom out, Reset, and movement controls also work without gestures. Tap Close photo to return. Photo-editing controls still open the crop editor."),
            .init("lock.open", "History remains visible", "Past history is readable without sharing today. Unstarted prompts are hidden from Timeline; Today waits until the invitation has started. You can still share means entry is available, including the first-day exception. Future days are not shown as missed. Missed, locked, late, and still-open states explain what happened without relying on color alone."),
        ]
        case .responses: [
            .init("text.bubble", "Reply simply", "Use the small response box, microphone, and send button on Today. A current-day blessing opened from Timeline can also accept a response. Historical blessings are read-only."),
            .init("waveform", "Text or voice", "Voice responses include both recorded audio and a transcript. You can listen before sending. Responses do not support photos or video."),
            .init("person.crop.circle", "See who replied", "List and Threads cards show the number of responses and slightly overlapping profile photos of the people who replied. Each person appears once even if they replied more than once; the count includes every response. Cards with no responses leave this line hidden. Response rows show the person's profile photo beside their name. Open a blessing to read responses or listen to saved/available audio."),
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
            .init("square.grid.2x2", "Add a Home Screen widget", "Touch and hold the Home Screen, choose Edit → Add Widget, search for manna circle, and choose a size. During sharing time, tap it to open Today. Otherwise it rotates visible blessings; tap one to open it. Older blessings open without first loading their Timeline page; normal privacy rules still apply."),
            .init("arrow.clockwise", "Refresh a widget", "Open manna after signing in or joining a circle to refresh its shared widget data. After restarting your phone, unlock it once. Widgets prepare known sharing times in advance, but iOS controls refresh timing; they cannot fetch new blessings while the app has not refreshed."),
            .init("gearshape", "Control the experience", "Choose the widget refresh interval in User settings, default 30 minutes. iOS controls exact refresh and delivery timing. If alerts or Live Activities are missing, check their permissions in iPhone Settings."),
        ]
        case .personalization: [
            .init("person.crop.circle", "Start with your profile", "Setup offers a Your profile step to review your Apple-provided name and choose an optional square-cropped photo. Continue keeps your current profile. You can edit it later in User settings."),
            .init("person.crop.circle.badge.checkmark", "Your account", "The sign-in screen shows the manna logo. To sign out, open User settings and scroll to Sign out; it is not in the app menu or Circle page."),
            .init("person.crop.circle", "Your profile", "Use User settings to change your name and profile photo. Profile and circle photos use a circular preview; pinch and drag together to crop, or use Adjust photo to zoom and move without gestures. VoiceOver also offers crop actions. The uploaded image is square."),
            .init("circle.lefthalf.filled", "Light, dark, or automatic", "Choose appearance in User settings. Automatic follows your device. Colors keep text readable in both appearances. Choose your app icon separately; the logo artwork is also used in manna's branded surfaces."),
            .init("waveform.path.ecg", "Help test reliability", "User settings has an optional Share diagnostic data switch. For new accounts on this device, this field-testing build starts with sharing on. You can turn it off in User settings. Your saved choice is kept across launches and updates, including TestFlight; an existing saved off setting remains off. While manna is open, small batches send timings, sizes, failure sources, short error codes and categories, app build, and a random session code to the developer. This includes network, speech, recording, and diagnostic-upload failures such as connection limits. Error messages are checked on this device for a connection-limit category; the messages themselves are not sent. Reports are linked to your signed-in account and retained for 14 days with scheduled cleanup. They exclude blessing text, recordings, photos, names, links, and credentials. Other circle members cannot read them. Send diagnostics now sends one queued batch. New error records go ahead of routine timing records, except that an upload already attempted must retry its original batch unchanged. Repeated retries of the same upload failure add only one error record until a batch succeeds. Turning sharing off discards unsent records; an upload already underway may finish. The device queue holds up to 1,000 recent records and removes older routine records first when full. It discards records older than 13 days when collection next opens, and may lose the last two seconds before a crash. Local demo keeps metrics on this device."),
            .init("line.3.horizontal", "Find your way back", "The hamburger menu keeps Help, About, User settings, and circle management within reach. You can revisit this guide whenever you need it."),
        ]
        case .accessibility: [
            .init("textformat.size", "Larger text & readable colors", "manna follows your iPhone's text size, Reduce Motion, and contrast settings. Choose Light, Dark, or Automatic in User settings. Sharing states use words and symbols, not just color."),
            .init("list.bullet", "An easier Timeline", "Timeline opens in List for everyone, with one vertical stream of dates, people, and blessings. Use Filter by person to choose All or one person in List. Use the wide Timeline layout button in the top bar to choose Threads for member lanes; the person filter does not apply to Threads. Both layouts support larger text and VoiceOver."),
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

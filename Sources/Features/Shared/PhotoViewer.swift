import SwiftUI
import UIKit

/// Displayed photos open a viewer; edit controls and card navigation keep their own actions.
extension View {
    func photoEnlargement(url: URL?, title: String, hitSlop: CGFloat = 0) -> some View {
        modifier(PhotoEnlargementModifier(url: url, title: title, hitSlop: hitSlop))
    }
}

private struct PhotoEnlargementModifier: ViewModifier {
    let url: URL?
    let title: String
    let hitSlop: CGFloat
    @State private var isPresented = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if let url {
            content
                .accessibilityElement(children: .ignore)
                .contentShape(Rectangle().inset(by: -hitSlop))
                .onTapGesture { isPresented = true }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(title)
                .accessibilityHint("Open full screen to zoom")
                .accessibilityAction { isPresented = true }
                .fullScreenCover(isPresented: $isPresented) {
                    FullscreenPhotoViewer(url: url, title: title)
                }
                .onChange(of: self.url) { _, _ in isPresented = false }
        } else {
            content
        }
    }
}

struct BlessingPhotoView: View {
    let url: URL

    var body: some View {
        Group {
            if url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image): image.resizable().scaledToFit()
                    case .failure:
                        ContentUnavailableView("Photo unavailable", systemImage: "photo.badge.exclamationmark")
                    case .empty:
                        ZStack {
                            AppTheme.canvas
                            ProgressView().accessibilityLabel("Loading photo")
                        }
                        .frame(height: 220)
                    @unknown default: EmptyView()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 520)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier("blessing.photo")
        .photoEnlargement(url: url, title: "Blessing photo")
    }
}

private struct FullscreenPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let url: URL
    let title: String
    @State private var image: UIImage?
    @State private var failed = false
    @State private var zoom: CGFloat = 1
    @State private var movement = PhotoMovement()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline).lineLimit(2)
                Spacer(minLength: 12)
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.12), in: Circle())
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close photo")
                    .accessibilityIdentifier("photo.close")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Group {
                if let image {
                    ZoomablePhoto(image: image, zoom: $zoom, movement: movement)
                        .accessibilityLabel(title)
                        .accessibilityValue("\(Int((zoom * 100).rounded())) percent zoom")
                        .accessibilityIdentifier("photo.zoomImage")
                } else if failed {
                    ContentUnavailableView("Photo unavailable", systemImage: "photo.badge.exclamationmark",
                        description: Text("Close the photo and try again when you’re connected."))
                } else {
                    ProgressView().tint(.white).accessibilityLabel("Loading photo")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if image != nil {
                HStack(spacing: 16) {
                    Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom = max(1, zoom / 1.5) }
                        .disabled(zoom <= 1.01)
                    Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom = min(5, zoom * 1.5) }
                        .disabled(zoom >= 4.99)
                    Button("Reset", systemImage: "arrow.counterclockwise") { zoom = 1; movement = PhotoMovement() }
                    Menu("Move photo", systemImage: "arrow.up.and.down.and.arrow.left.and.right") {
                        Button("Move left") { move(x: -80) }
                        Button("Move right") { move(x: 80) }
                        Button("Move up") { move(y: -80) }
                        Button("Move down") { move(y: 80) }
                    }
                    .disabled(zoom <= 1.01)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(PhotoViewerControlStyle())
                .padding(12)
            }
        }
        .foregroundStyle(.white)
        .background { Color.black.ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .task(id: url) {
            image = nil
            failed = false
            do {
                let loaded: UIImage?
                if url.isFileURL {
                    loaded = UIImage(contentsOfFile: url.path)
                } else {
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else {
                        failed = true
                        return
                    }
                    loaded = UIImage(data: data)
                }
                guard !Task.isCancelled else { return }
                image = loaded
                failed = loaded == nil
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    private func move(x: CGFloat = 0, y: CGFloat = 0) {
        movement = PhotoMovement(x: x, y: y)
    }
}

private struct PhotoViewerControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: 44, minHeight: 44)
            .background(.white.opacity(configuration.isPressed ? 0.24 : 0.12), in: Capsule())
    }
}

private struct PhotoMovement: Equatable {
    let id = UUID()
    var x: CGFloat = 0
    var y: CGFloat = 0
}

/// UIScrollView provides native pinch, pan, zoom limits, and centering for any image aspect ratio.
private struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage
    @Binding var zoom: CGFloat
    let movement: PhotoMovement

    func makeCoordinator() -> Coordinator { Coordinator(zoom: $zoom) }

    func makeUIView(context: Context) -> PhotoZoomScrollView {
        let view = PhotoZoomScrollView(image: image)
        view.delegate = context.coordinator
        view.isAccessibilityElement = true
        view.accessibilityTraits = .image
        view.accessibilityIdentifier = "photo.zoomImage"
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        return view
    }

    func updateUIView(_ view: PhotoZoomScrollView, context: Context) {
        context.coordinator.zoom = $zoom
        context.coordinator.isUpdating = true
        view.relativeZoom = zoom
        if context.coordinator.lastMovement != movement.id {
            context.coordinator.lastMovement = movement.id
            view.move(x: movement.x, y: movement.y)
        }
        context.coordinator.isUpdating = false
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var zoom: Binding<CGFloat>
        var lastMovement: UUID?
        var isUpdating = false
        init(zoom: Binding<CGFloat>) { self.zoom = zoom }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            (scrollView as? PhotoZoomScrollView)?.photo
        }
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard let view = scrollView as? PhotoZoomScrollView else { return }
            view.centerPhoto()
            let value = view.relativeZoom
            if !isUpdating && abs(zoom.wrappedValue - value) > 0.001 { zoom.wrappedValue = value }
        }
        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view as? PhotoZoomScrollView else { return }
            if view.relativeZoom > 1.01 {
                zoom.wrappedValue = 1
            } else {
                // Zoom about the tapped point, as in the system Photos viewer.
                let point = recognizer.location(in: view.photo)
                let scale = view.minimumZoomScale * 2
                let size = CGSize(width: view.bounds.width / scale, height: view.bounds.height / scale)
                view.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                    width: size.width, height: size.height), animated: false)
            }
        }
    }
}

private final class PhotoZoomScrollView: UIScrollView {
    let photo: UIImageView
    private var previousSize: CGSize = .zero
    var relativeZoom: CGFloat {
        get { minimumZoomScale > 0 ? zoomScale / minimumZoomScale : 1 }
        set {
            guard previousSize != .zero else { return }
            let requested = minimumZoomScale * min(5, max(1, newValue))
            if abs(zoomScale - requested) > 0.001 { setZoomScale(requested, animated: false) }
        }
    }

    init(image: UIImage) {
        photo = UIImageView(image: image)
        super.init(frame: .zero)
        backgroundColor = .black
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        photo.frame = CGRect(origin: .zero, size: image.size)
        addSubview(photo)
        contentSize = image.size
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0, let image = photo.image,
              image.size.width > 0, image.size.height > 0 else { return }
        if bounds.size != previousSize {
            previousSize = bounds.size
            let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
            minimumZoomScale = fit
            maximumZoomScale = fit * 5
            zoomScale = fit
            centerPhoto()
            setContentOffset(CGPoint(x: -contentInset.left, y: -contentInset.top), animated: false)
        }
        centerPhoto()
    }

    func centerPhoto() {
        let inset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: max(0, (bounds.width - contentSize.width) / 2), bottom: 0, right: 0)
        if contentInset != inset { contentInset = inset }
    }

    func move(x: CGFloat, y: CGFloat) {
        let minX = -contentInset.left
        let minY = -contentInset.top
        let maxX = max(minX, contentSize.width - bounds.width)
        let maxY = max(minY, contentSize.height - bounds.height)
        setContentOffset(CGPoint(x: min(maxX, max(minX, contentOffset.x - x)),
            y: min(maxY, max(minY, contentOffset.y - y))), animated: false)
    }
}

#if DEBUG
/// Synthetic, device-local artwork for UI checks; activated only by the local test launch argument.
@MainActor
enum PhotoViewerUITestFixture {
    static func makePhoto() -> URL? {
        let size = CGSize(width: 800, height: 1_100)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for row in 0..<5 {
                for column in 0..<4 {
                    UIColor(white: (row + column).isMultiple(of: 2) ? 0.9 : 0.2, alpha: 0.9).setFill()
                    context.fill(CGRect(x: CGFloat(40 + column * 190), y: CGFloat(50 + row * 210), width: 150, height: 170))
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Manna-Photo-UI-Fixture.jpg")
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
}
#endif

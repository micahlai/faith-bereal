import SwiftUI
import UIKit

struct PendingPhotoResize: Identifiable {
    let id = UUID()
    let image: UIImage

    init(data: Data) throws {
        guard let image = UIImage(data: data) else {
            throw BlessingError.cameraUnavailable
        }
        self.image = image
    }
}

struct PhotoResizeEditor: View {
    let title: String
    let photo: PendingPhotoResize
    let onCancel: () -> Void
    let onUsePhoto: (URL) -> Void

    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var viewportSize = CGSize(width: 1, height: 1)
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Pinch with two fingers to zoom, then drag to choose the square crop.")
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .multilineTextAlignment(.center)

                    photoViewport
                    Menu("Adjust photo", systemImage: "crop") {
                        Button("Zoom in") { adjustZoom(by: 0.25) }
                        Button("Zoom out") { adjustZoom(by: -0.25) }
                        Button("Move left") { movePhoto(x: -20, y: 0) }
                        Button("Move right") { movePhoto(x: 20, y: 0) }
                        Button("Move up") { movePhoto(x: 0, y: -20) }
                        Button("Move down") { movePhoto(x: 0, y: 20) }
                        Button("Reset crop", action: resetCrop)
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("Adjust the crop without pinching or dragging")
                    Text("You can also use Adjust photo to zoom, move, or reset the crop.")
                        .font(.footnote)
                        .foregroundStyle(AppTheme.secondaryInk)
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.vertical, 20)
            }
            .background(AppTheme.canvas.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("photo-resize-editor")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Photo", action: usePhoto)
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("use-resized-photo")
                }
            }
        }
        .presentationDetents([.large])
        .alert(
            "Couldn’t resize photo",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please choose another photo.")
        }
    }

    private var photoViewport: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let baseSize = baseImageSize(viewportSize: size)

            ZStack {
                Color.black
                Image(uiImage: photo.image)
                    .resizable()
                    .frame(width: baseSize.width, height: baseSize.height)
                    .scaleEffect(zoom)
                    .offset(offset)
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .clipShape(Circle())
            .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: 2).allowsHitTesting(false) }
            .contentShape(Circle())
            .gesture(
                dragGesture(viewportSize: size)
                    .simultaneously(with: magnifyGesture(viewportSize: size))
            )
            .onAppear { updateViewportSize(size) }
            .onChange(of: size) { _, newSize in updateViewportSize(newSize) }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 420, maxHeight: 420)
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Square photo crop preview")
        .accessibilityValue("Zoom \(Int(zoom * 100)) percent")
        .accessibilityHint("Adjust zoom or use the actions to move and reset the photo")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjustZoom(by: 0.25)
            case .decrement: adjustZoom(by: -0.25)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Move left") { movePhoto(x: -20, y: 0) }
        .accessibilityAction(named: "Move right") { movePhoto(x: 20, y: 0) }
        .accessibilityAction(named: "Move up") { movePhoto(x: 0, y: -20) }
        .accessibilityAction(named: "Move down") { movePhoto(x: 0, y: 20) }
        .accessibilityAction(named: "Reset crop") { resetCrop() }
    }

    private func dragGesture(viewportSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                offset = constrainedOffset(
                    CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    ),
                    zoom: zoom,
                    viewportSize: viewportSize
                )
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func magnifyGesture(viewportSize: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value.magnification, 1), 4)
                offset = constrainedOffset(offset, zoom: zoom, viewportSize: viewportSize)
            }
            .onEnded { _ in
                committedZoom = zoom
                committedOffset = offset
            }
    }

    private func usePhoto() {
        do {
            let url = try CaptureMediaStore.persistResizedProfilePhoto(
                image: photo.image,
                viewportSize: viewportSize,
                zoom: zoom,
                offset: offset
            )
            onUsePhoto(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func adjustZoom(by amount: CGFloat) {
        zoom = min(max(zoom + amount, 1), 4)
        offset = constrainedOffset(offset, zoom: zoom, viewportSize: viewportSize)
        committedZoom = zoom
        committedOffset = offset
    }

    private func movePhoto(x: CGFloat, y: CGFloat) {
        offset = constrainedOffset(
            CGSize(width: offset.width + x, height: offset.height + y),
            zoom: zoom, viewportSize: viewportSize)
        committedOffset = offset
    }

    private func resetCrop() {
        zoom = 1
        committedZoom = 1
        offset = .zero
        committedOffset = .zero
    }

    private func updateViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewportSize = size
        offset = constrainedOffset(offset, zoom: zoom, viewportSize: size)
        committedOffset = offset
    }

    private func baseImageSize(viewportSize: CGSize) -> CGSize {
        let imageSize = photo.image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return viewportSize
        }
        let fillScale = max(
            viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        return CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
    }

    private func constrainedOffset(
        _ proposed: CGSize,
        zoom: CGFloat,
        viewportSize: CGSize
    ) -> CGSize {
        let baseSize = baseImageSize(viewportSize: viewportSize)
        let maxX = max(0, (baseSize.width * zoom - viewportSize.width) / 2)
        let maxY = max(0, (baseSize.height * zoom - viewportSize.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var viewportSize = CGSize(width: 1, height: 1)
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Move and resize the photo while keeping its original proportions.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .multilineTextAlignment(.center)

                photoViewport

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Image(systemName: "minus.magnifyingglass")
                            .accessibilityHidden(true)
                        Slider(
                            value: Binding(
                                get: { zoom },
                                set: { setZoom($0) }
                            ),
                            in: 1...4
                        )
                        .accessibilityLabel("Photo size")
                        .accessibilityValue("\(Int((zoom * 100).rounded())) percent")
                        Image(systemName: "plus.magnifyingglass")
                            .accessibilityHidden(true)
                    }

                    HStack(spacing: 10) {
                        nudgeButton("Move left", systemImage: "arrow.left", x: -16, y: 0)
                        nudgeButton("Move up", systemImage: "arrow.up", x: 0, y: -16)
                        Button("Reset") { resetPhoto() }
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                        nudgeButton("Move down", systemImage: "arrow.down", x: 0, y: 16)
                        nudgeButton("Move right", systemImage: "arrow.right", x: 16, y: 0)
                    }
                }
                .frame(maxWidth: 520)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.top, 20)
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
        .alert("Couldn’t resize photo", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
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
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(viewportSize: size))
            .simultaneousGesture(magnifyGesture(viewportSize: size))
            .onAppear { updateViewportSize(size) }
            .onChange(of: size) { _, newSize in updateViewportSize(newSize) }
            .accessibilityLabel("Photo resize preview")
            .accessibilityHint("Use the photo size slider and move buttons to adjust the framing")
        }
        .aspectRatio(photoAspectRatio, contentMode: .fit)
        .frame(maxWidth: 520, maxHeight: 460)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
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

    private func nudgeButton(
        _ label: String,
        systemImage: String,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        Button {
            offset = constrainedOffset(
                CGSize(width: offset.width + x, height: offset.height + y),
                zoom: zoom,
                viewportSize: viewportSize
            )
            committedOffset = offset
        } label: {
            Image(systemName: systemImage)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(label)
    }

    private func setZoom(_ newZoom: CGFloat) {
        zoom = min(max(newZoom, 1), 4)
        committedZoom = zoom
        offset = constrainedOffset(offset, zoom: zoom, viewportSize: viewportSize)
        committedOffset = offset
    }

    private func resetPhoto() {
        let changes = {
            zoom = 1
            committedZoom = 1
            offset = .zero
            committedOffset = .zero
        }
        if reduceMotion {
            changes()
        } else {
            withAnimation(.snappy(duration: 0.2), changes)
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

    private func updateViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewportSize = size
        offset = constrainedOffset(offset, zoom: zoom, viewportSize: size)
        committedOffset = offset
    }

    private var photoAspectRatio: CGFloat {
        let imageSize = photo.image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return imageSize.width / imageSize.height
    }

    private func baseImageSize(viewportSize: CGSize) -> CGSize {
        let imageSize = photo.image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return viewportSize
        }
        let fillScale = max(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
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

import SwiftUI
import UIKit

struct PendingSquarePhoto: Identifiable {
    let id = UUID()
    let image: UIImage

    init(data: Data) throws {
        guard let image = UIImage(data: data) else {
            throw BlessingError.cameraUnavailable
        }
        self.image = image
    }
}

struct SquarePhotoEditor: View {
    let title: String
    let photo: PendingSquarePhoto
    let onCancel: () -> Void
    let onUsePhoto: (URL) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var cropSide: CGFloat = 1
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Move and resize the photo inside the square.")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)
                    .multilineTextAlignment(.center)

                cropViewport

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
                        Button("Reset") { resetCrop() }
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
            .accessibilityIdentifier("square-photo-editor")
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

    private var cropViewport: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let baseSize = baseImageSize(viewportSide: side)

            ZStack {
                Color.black
                Image(uiImage: photo.image)
                    .resizable()
                    .frame(width: baseSize.width, height: baseSize.height)
                    .scaleEffect(zoom)
                    .offset(offset)
            }
            .frame(width: side, height: side)
            .clipped()
            .overlay {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(viewportSide: side))
            .simultaneousGesture(magnifyGesture(viewportSide: side))
            .onAppear { updateViewportSide(side) }
            .onChange(of: side) { _, newSide in updateViewportSide(newSide) }
            .accessibilityLabel("Photo crop preview")
            .accessibilityHint("Use the photo size slider and move buttons to adjust the crop")
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 520)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
    }

    private func dragGesture(viewportSide: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                offset = constrainedOffset(
                    CGSize(
                        width: committedOffset.width + value.translation.width,
                        height: committedOffset.height + value.translation.height
                    ),
                    zoom: zoom,
                    viewportSide: viewportSide
                )
            }
            .onEnded { _ in committedOffset = offset }
    }

    private func magnifyGesture(viewportSide: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value.magnification, 1), 4)
                offset = constrainedOffset(offset, zoom: zoom, viewportSide: viewportSide)
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
                viewportSide: cropSide
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
        offset = constrainedOffset(offset, zoom: zoom, viewportSide: cropSide)
        committedOffset = offset
    }

    private func resetCrop() {
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
            let url = try CaptureMediaStore.persistCroppedProfilePhoto(
                image: photo.image,
                viewportSize: cropSide,
                zoom: zoom,
                offset: offset
            )
            onUsePhoto(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateViewportSide(_ side: CGFloat) {
        guard side > 0 else { return }
        cropSide = side
        offset = constrainedOffset(offset, zoom: zoom, viewportSide: side)
        committedOffset = offset
    }

    private func baseImageSize(viewportSide: CGFloat) -> CGSize {
        let imageSize = photo.image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: viewportSide, height: viewportSide)
        }
        let fillScale = max(viewportSide / imageSize.width, viewportSide / imageSize.height)
        return CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
    }

    private func constrainedOffset(
        _ proposed: CGSize,
        zoom: CGFloat,
        viewportSide: CGFloat
    ) -> CGSize {
        let baseSize = baseImageSize(viewportSide: viewportSide)
        let maxX = max(0, (baseSize.width * zoom - viewportSide) / 2)
        let maxY = max(0, (baseSize.height * zoom - viewportSide) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }
}

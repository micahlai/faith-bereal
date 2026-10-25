import SwiftUI
import UIKit

/// A disk hit is shown before refreshing a signed URL. Cached metadata can never
/// start a network request; only the live model supplies verified photo URLs.
struct IdentityPhotoImage<Placeholder: View>: View {
    @Environment(AppModel.self) private var model
    let key: IdentityPhotoCache.Key
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var loadedData: Data?
    @State private var loadedAccountID: UUID?
    @State private var loadedKey: IdentityPhotoCache.Key?

    private struct Load: Hashable {
        let accountID: UUID?
        let key: IdentityPhotoCache.Key
        let url: URL?
        let allowNetwork: Bool
    }
    private var load: Load {
        Load(accountID: model.currentUser?.id, key: key, url: url,
             allowNetwork: model.canRefreshIdentityPhoto(key: key, sourceURL: url))
    }

    var body: some View {
        Group {
            if let url, url.isFileURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let accountID = model.currentUser?.id, loadedAccountID == accountID,
                      loadedKey == key, let loadedData, let image = UIImage(data: loadedData) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: load) {
            let request = load
            guard url?.isFileURL != true, let accountID = request.accountID else { return }
            if loadedAccountID != accountID || loadedKey != key { loadedData = nil }
            loadedAccountID = accountID
            loadedKey = key
            if let cached = await model.identityPhotoCache.cachedData(accountID: accountID, key: request.key),
               !Task.isCancelled, load == request {
                loadedData = cached
            }
            let fetched = await model.identityPhotoCache.imageData(accountID: accountID, key: request.key,
                sourceURL: request.url, allowNetwork: request.allowNetwork)
            guard !Task.isCancelled, load == request else { return }
            loadedData = fetched
        }
    }
}

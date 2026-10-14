import Foundation
import Supabase

extension PostgrestBuilder {
    @discardableResult
    func measuredExecute(_ kind: BackendRequestKind, diagnostics: BackendDiagnostics = .shared) async throws -> PostgrestResponse<Void> {
        let span = diagnostics.beginRequest(kind)
        do {
            let response = try await execute()
            span.finish(httpStatus: response.status, receivedBytes: Int64(response.data.count))
            return response
        } catch {
            // The SDK consumes error HTTP responses; never infer their status or log bodies.
            span.finish(error: error)
            throw error
        }
    }

    func measuredExecute<T: Decodable>(_ kind: BackendRequestKind, diagnostics: BackendDiagnostics = .shared) async throws -> PostgrestResponse<T> {
        let span = diagnostics.beginRequest(kind)
        do {
            let response: PostgrestResponse<T> = try await execute()
            span.finish(httpStatus: response.status, receivedBytes: Int64(response.data.count))
            return response
        } catch {
            span.finish(error: error)
            throw error
        }
    }
}

extension StorageFileApi {
    func measuredUpload(_ path: String, data: Data, options: FileOptions,
        diagnostics: BackendDiagnostics = .shared) async throws -> FileUploadResponse {
        let span = diagnostics.beginRequest(.storageUpload, payloadBytes: Int64(data.count))
        do {
            let response = try await upload(path, data: data, options: options)
            span.finish()
            return response
        } catch {
            span.finish(error: error)
            throw error
        }
    }

    func measuredUpload(_ path: String, fileURL: URL, options: FileOptions,
        diagnostics: BackendDiagnostics = .shared) async throws -> FileUploadResponse {
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        let span = diagnostics.beginRequest(.storageUpload, payloadBytes: size)
        do {
            let response = try await upload(path, fileURL: fileURL, options: options)
            span.finish()
            return response
        } catch {
            span.finish(error: error)
            throw error
        }
    }

    func measuredSignedURL(path: String, expiresIn: Int,
        diagnostics: BackendDiagnostics = .shared) async throws -> URL {
        let span = diagnostics.beginRequest(.storageSign)
        do {
            let response: URL = try await createSignedURL(path: path, expiresIn: expiresIn)
            span.finish()
            return response
        } catch {
            span.finish(error: error)
            throw error
        }
    }

    func measuredRemove(paths: [String]) async throws -> [FileObject] {
        let span = BackendDiagnostics.shared.beginRequest(.storageOther)
        do {
            let response = try await remove(paths: paths)
            span.finish()
            return response
        } catch {
            span.finish(error: error)
            throw error
        }
    }
}

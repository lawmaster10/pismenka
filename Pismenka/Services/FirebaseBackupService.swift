//
//  FirebaseBackupService.swift
//  Pismenka
//
//  Mirrors the local JSON-backed profile store into Firestore so reinstalling
//  and signing in with the same Google account can recover long-lived progress.
//

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import GoogleSignIn
import Network
import UIKit

enum FirebaseBootstrap {
    private static var didConfigure = false

    static var isConfigured: Bool {
        didConfigure
    }

    @discardableResult
    static func configureIfPossible() -> Bool {
        guard !didConfigure else { return true }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return false
        }
        FirebaseApp.configure()
        didConfigure = true
        return true
    }
}

struct CloudBackupEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int = CloudBackupEnvelope.currentSchemaVersion
    var savedAt: Date = Date()
    var appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    var profiles: [Profile]
    var settings: AppSettingsSnapshot
}

struct CloudBackupMergeResult: Equatable {
    var profiles: [Profile]
    var didChangeLocalProfiles: Bool
}

enum FirebaseBackupStatus: Equatable {
    case notConfigured
    case signedOut
    case syncing
    case synced(Date)
    case restored(Date)
    case tooLarge(Int)
    case offline
    case failed(String)
}

@MainActor
final class FirebaseBackupService: ObservableObject {
    nonisolated static let maxPayloadBytes = 900_000
    private static let cloudBackupDebounceInterval: TimeInterval = 2.0

    @Published private(set) var status: FirebaseBackupStatus = .signedOut
    @Published private(set) var signedInEmail: String?

    private weak var profileManager: ProfileManager?
    private weak var settings: AppSettings?
    private let networkMonitor = NWPathMonitor()
    private let networkMonitorQueue = DispatchQueue(label: "Pismenka.FirebaseBackup.NetworkMonitor")
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var cloudBackupWorkItem: DispatchWorkItem?
    private var pendingBackup: (profiles: [Profile], settings: AppSettingsSnapshot)?
    private var backupGeneration = 0
    private var hasStarted = false
    private var hasStartedNetworkMonitor = false
    private var networkStatus: NWPath.Status = .requiresConnection
    private var isApplyingCloudSnapshot = false

    var isSignedIn: Bool { signedInEmail != nil }
    private var isNetworkAvailable: Bool { networkStatus == .satisfied }

    deinit {
        networkMonitor.cancel()
        cloudBackupWorkItem?.cancel()
        for observer in lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let authHandle, FirebaseBootstrap.isConfigured {
            Auth.auth().removeStateDidChangeListener(authHandle)
        }
    }

    func start(profileManager: ProfileManager, settings: AppSettings) {
        guard !hasStarted else { return }
        hasStarted = true
        self.profileManager = profileManager
        self.settings = settings
        startNetworkMonitor()

        profileManager.onProfilesSaved = { [weak self, weak settings] profiles in
            guard let settings else { return }
            Task { @MainActor in
                self?.backup(profiles: profiles, settings: settings.snapshot())
            }
        }

        settings.onSettingsChanged = { [weak self, weak profileManager] snapshot in
            Task { @MainActor in
                self?.backup(profiles: profileManager?.profiles ?? [], settings: snapshot)
            }
        }
        installLifecycleObservers()

        guard FirebaseBootstrap.isConfigured else {
            status = .notConfigured
            return
        }

        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self else { return }
                self.signedInEmail = user?.email
                if user == nil {
                    self.cancelScheduledBackup()
                    self.status = .signedOut
                } else {
                    await self.restoreAndMergeFromCloud()
                }
            }
        }
    }

    func handleOpenURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    func signInWithGoogle() {
        guard FirebaseBootstrap.isConfigured else {
            status = .notConfigured
            return
        }
        guard isNetworkAvailable else {
            status = .offline
            return
        }
        guard let presenting = Self.presentingViewController else {
            status = .failed("Písmenka couldn't open the Google sign-in screen.")
            return
        }
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            status = .failed("Firebase is missing the Google client ID.")
            return
        }

        status = .syncing
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: presenting) { result, error in
            if let error {
                Task { @MainActor in
                    self.status = .failed(error.localizedDescription)
                }
                return
            }
            guard let user = result?.user,
                  let idToken = user.idToken?.tokenString else {
                Task { @MainActor in
                    self.status = .failed("Google sign-in did not return an ID token.")
                }
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )
            Auth.auth().signIn(with: credential) { _, error in
                Task { @MainActor in
                    if let error {
                        self.status = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    func signOut() {
        guard FirebaseBootstrap.isConfigured else {
            status = .notConfigured
            return
        }
        GIDSignIn.sharedInstance.signOut()
        do {
            cancelScheduledBackup()
            try Auth.auth().signOut()
            signedInEmail = nil
            status = .signedOut
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func backupNow() {
        Task { @MainActor in
            await forceSyncNow()
        }
    }

    func restoreNow() {
        Task { @MainActor in
            await restoreAndMergeFromCloud()
        }
    }

    func backup(profiles: [Profile], settings: AppSettingsSnapshot) {
        scheduleBackup(profiles: profiles, settings: settings)
    }

    private func forceSyncNow() async {
        guard let profileManager, let settings else { return }
        cancelScheduledBackup()
        profileManager.flushPendingSave()
        // Flushing local state can invoke `onProfilesSaved`; force sync should
        // own the next write.
        cancelScheduledBackup()
        await performBackup(
            profiles: profileManager.profiles,
            settings: settings.snapshot(),
            waitForServerAcknowledgement: true
        )
    }

    private func scheduleBackup(profiles: [Profile], settings: AppSettingsSnapshot) {
        guard !isApplyingCloudSnapshot else { return }
        pendingBackup = (profiles, settings)
        cloudBackupWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self, let pendingBackup = self.pendingBackup else { return }
                self.pendingBackup = nil
                await self.performBackup(
                    profiles: pendingBackup.profiles,
                    settings: pendingBackup.settings,
                    waitForServerAcknowledgement: false
                )
            }
        }
        cloudBackupWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.cloudBackupDebounceInterval,
            execute: workItem
        )
    }

    private func cancelScheduledBackup() {
        cloudBackupWorkItem?.cancel()
        cloudBackupWorkItem = nil
        pendingBackup = nil
    }

    private func performBackup(
        profiles: [Profile],
        settings: AppSettingsSnapshot,
        successStatus: FirebaseBackupStatus? = nil,
        waitForServerAcknowledgement: Bool
    ) async {
        guard !isApplyingCloudSnapshot else { return }
        guard FirebaseBootstrap.isConfigured else {
            status = .notConfigured
            return
        }
        guard let user = Auth.auth().currentUser else {
            status = .signedOut
            return
        }
        guard isNetworkAvailable else {
            pendingBackup = (profiles, settings)
            status = .offline
            return
        }

        let generation = nextBackupGeneration()
        status = .syncing
        let envelope = CloudBackupEnvelope(profiles: profiles, settings: settings)
        do {
            let fields = try Self.backupDocumentFields(for: envelope)
            guard let payloadBytes = fields["payloadBytes"] as? Int else {
                status = .failed("Písmenka couldn't prepare the Google backup.")
                return
            }
            guard payloadBytes <= Self.maxPayloadBytes else {
                status = .tooLarge(payloadBytes)
                return
            }

            if waitForServerAcknowledgement {
                try await Firestore.firestore().enableNetwork()
                try await backupDocument(userId: user.uid).setData(fields)
                try await Firestore.firestore().waitForPendingWrites()
                guard isCurrentBackupGeneration(generation) else { return }
                status = successStatus ?? .synced(envelope.savedAt)
            } else {
                try await backupDocument(userId: user.uid).setData(fields)
                guard isCurrentBackupGeneration(generation) else { return }
                status = successStatus ?? .synced(envelope.savedAt)
            }
        } catch {
            guard isCurrentBackupGeneration(generation) else { return }
            status = .failed(error.localizedDescription)
        }
    }

    private func restoreAndMergeFromCloud() async {
        cancelScheduledBackup()
        guard FirebaseBootstrap.isConfigured else {
            status = .notConfigured
            return
        }
        guard let user = Auth.auth().currentUser else {
            status = .signedOut
            return
        }
        guard let profileManager, let settings else {
            status = .failed("Firebase backup service was not connected to app state.")
            return
        }
        guard isNetworkAvailable else {
            status = .offline
            return
        }

        status = .syncing
        do {
            let snapshot = try await backupDocument(userId: user.uid).getDocument()
            guard let data = snapshot.data(), let payload = data["payload"] as? Data else {
                await performBackup(
                    profiles: profileManager.profiles,
                    settings: settings.snapshot(),
                    waitForServerAcknowledgement: false
                )
                return
            }

            let envelope = try Self.decodePayload(payload)
            guard envelope.schemaVersion == CloudBackupEnvelope.currentSchemaVersion else {
                status = .failed("This Google backup was made by an unsupported version.")
                return
            }

            let merge = Self.mergedProfiles(local: profileManager.profiles, cloud: envelope.profiles)
            var appliedSomething = false
            do {
                isApplyingCloudSnapshot = true
                defer { isApplyingCloudSnapshot = false }

                if merge.didChangeLocalProfiles {
                    profileManager.replaceProfilesFromCloud(merge.profiles)
                    appliedSomething = true
                }

                if settings.apply(snapshot: envelope.settings) {
                    appliedSomething = true
                }
            }

            await performBackup(
                profiles: profileManager.profiles,
                settings: settings.snapshot(),
                successStatus: appliedSomething ? .restored(envelope.savedAt) : nil,
                waitForServerAcknowledgement: false
            )
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func backupDocument(userId: String) -> DocumentReference {
        Firestore.firestore()
            .collection("users")
            .document(userId)
            .collection("backups")
            .document("current")
    }

    private func startNetworkMonitor() {
        guard !hasStartedNetworkMonitor else { return }
        hasStartedNetworkMonitor = true
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handleNetworkPathUpdate(path.status)
            }
        }
        networkMonitor.start(queue: networkMonitorQueue)
    }

    private func handleNetworkPathUpdate(_ status: NWPath.Status) {
        let wasOffline = !isNetworkAvailable
        networkStatus = status

        guard FirebaseBootstrap.isConfigured else { return }
        if isNetworkAvailable {
            Task {
                try? await Firestore.firestore().enableNetwork()
            }
        } else {
            Task {
                try? await Firestore.firestore().disableNetwork()
            }
        }

        guard wasOffline, isNetworkAvailable, Auth.auth().currentUser != nil else { return }
        if let pendingBackup {
            scheduleBackup(profiles: pendingBackup.profiles, settings: pendingBackup.settings)
        } else if case .offline = self.status {
            restoreNow()
        }
    }

    private func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        lifecycleObservers = [
            NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncBeforeBackgrounding()
                }
            },
            NotificationCenter.default.addObserver(
                forName: UIApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.syncBeforeBackgrounding()
                }
            }
        ]
    }

    private func syncBeforeBackgrounding() {
        guard FirebaseBootstrap.isConfigured, Auth.auth().currentUser != nil, isNetworkAvailable else { return }
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PismenkaFirebaseBackup") {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }

        Task { @MainActor [weak self] in
            await self?.forceSyncNow()
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }
        }
    }

    private func nextBackupGeneration() -> Int {
        backupGeneration += 1
        return backupGeneration
    }

    private func isCurrentBackupGeneration(_ generation: Int) -> Bool {
        generation == backupGeneration
    }

    private static var presentingViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
    }

    nonisolated static func mergedProfiles(local: [Profile], cloud: [Profile]) -> CloudBackupMergeResult {
        var result = local
        var changed = false

        for cloudProfile in cloud {
            if let index = result.firstIndex(where: { $0.id == cloudProfile.id }) {
                if cloudProfile.modifiedAt > result[index].modifiedAt {
                    result[index] = cloudProfile
                    changed = true
                }
            } else if result.count < ProfileExportService.maxProfiles {
                result.append(cloudProfile)
                changed = true
            }
        }

        return CloudBackupMergeResult(profiles: result, didChangeLocalProfiles: changed)
    }

    nonisolated static func backupDocumentFields(for envelope: CloudBackupEnvelope) throws -> [String: Any] {
        let data = try encodePayload(envelope)
        return [
            "schemaVersion": envelope.schemaVersion,
            "savedAt": Timestamp(date: envelope.savedAt),
            "appVersion": envelope.appVersion,
            "payload": data,
            "payloadEncoding": "lzfse-marker-v1",
            "payloadBytes": data.count
        ]
    }

    nonisolated static func encodePayload(_ envelope: CloudBackupEnvelope) throws -> Data {
        let encoded = try JSONEncoder().encode(envelope)
        let compressed = try (encoded as NSData).compressed(using: .lzfse) as Data
        if compressed.count < encoded.count {
            return Data([1]) + compressed
        }
        return Data([0]) + encoded
    }

    nonisolated static func decodePayload(_ payload: Data) throws -> CloudBackupEnvelope {
        guard let marker = payload.first else {
            throw CocoaError(.coderReadCorrupt)
        }
        let body = payload.dropFirst()
        let data: Data
        switch marker {
        case 0:
            data = Data(body)
        case 1:
            data = try (Data(body) as NSData).decompressed(using: .lzfse) as Data
        default:
            throw CocoaError(.coderReadCorrupt)
        }
        return try JSONDecoder().decode(CloudBackupEnvelope.self, from: data)
    }

    nonisolated static func isPayloadWithinLimit(_ payload: Data) -> Bool {
        payload.count <= maxPayloadBytes
    }
}

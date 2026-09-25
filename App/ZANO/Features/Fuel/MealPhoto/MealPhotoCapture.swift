// App/ZANO/Features/Fuel/MealPhoto/MealPhotoCapture.swift
//
// Shared pieces for the two photo flows in this folder — `MealCaptureSheet` (spec 9.5: meal
// photo -> protein estimate) and `MealPrepCaptureSheet` (spec 3, Meal prep row: photo of prepped
// containers). Everything user-facing reads `Copy.fuel.mealPhoto`.
//
//   - `MealPhotoCaptureStage`: the capture screen. A 3:4 live viewfinder with corner-bracket
//     framing, a shutter, a library picker and (protein only) a type-it-in exit. Camera missing
//     (Simulator) or denied -> the viewfinder explains and the library/manual exits remain.
//   - `CameraPreview`: `UIImagePickerController` with its own controls hidden, so the SwiftUI
//     shutter drives `takePicture()` (UIKit only because no SwiftUI camera exists — CLAUDE.md).
//   - `MealPhotoProcessing`: downscale + JPEG encode + perceptual hash, off the main actor.
//   - `MealPhotoStore`: writes the JPEG into the App Group so `Meal.photoPath` is a real,
//     container-relative path (`Models/Meal.swift`: "Local path ... inside the App Group").
//   - `MealPhotoWorkingView` / `MealPhotoMessageView`: loading and message states.
//
// UNVERIFIED (no Mac/device): that `UIImagePickerController` with `showsCameraControls = false`
// lays its 4:3 preview flush to the top of its view (so a 3:4 frame of the same width is filled
// exactly) — long-standing documented behaviour, never run here. `AVCaptureDevice.requestAccess(
// for:)`'s async form and `Button`'s `buttonRepeatBehavior` (both iOS 17) are used as documented.

import SwiftUI
import PhotosUI
import AVFoundation
import UIKit
import Core

// MARK: - Processing

/// A camera/library photo reduced to what the flows need: an upload-sized JPEG and its
/// perceptual hash. `Sendable` so it can come back from a detached task.
struct PreparedMealPhoto: Sendable {
    let jpeg: Data
    /// `nil` if hashing failed — `PhotoDedupe` fails open, so a missing hash means "not a
    /// duplicate", never a rejection.
    let hash: PhotoHash?
}

enum MealPhotoProcessing {
    /// Long edge after downscaling: plenty for a vision model to read a plate, and keeps the
    /// upload far under the bucket's 10 MB cap (roughly 300-600 KB at this quality).
    static let maxLongEdge: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.75

    /// Downscale, encode and hash off the main actor. `UIImage` isn't guaranteed `Sendable`, so
    /// it's bound `nonisolated(unsafe)` for the hop: it's read-only from here on and the caller
    /// never mutates it.
    @MainActor
    static func prepare(_ image: UIImage) async -> PreparedMealPhoto? {
        nonisolated(unsafe) let source = image
        return await Task.detached(priority: .userInitiated) {
            prepareSynchronously(source)
        }.value
    }

    private static func prepareSynchronously(_ image: UIImage) -> PreparedMealPhoto? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let longEdge = max(image.size.width, image.size.height)
        let scale = min(1, maxLongEdge / longEdge)
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // Drawing bakes in `imageOrientation`, so the JPEG is upright without EXIF.
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = resized.jpegData(compressionQuality: jpegQuality) else { return nil }
        return PreparedMealPhoto(jpeg: jpeg, hash: PhotoDedupe.hash(of: resized))
    }
}

// MARK: - Local photo store

enum MealPhotoStore {
    static let folder = "MealPhotos"

    /// Writes `jpeg` into the App Group container and returns the container-relative path
    /// (`MealPhotos/<uuid>.jpg`) to store on `Meal.photoPath`. `nil` on any file error — the meal
    /// still logs, just without a photo on record.
    static func save(jpeg: Data, id: UUID) -> String? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier) else {
            return nil
        }
        let directory = container.appendingPathComponent(folder, isDirectory: true)
        let relativePath = "\(folder)/\(id.uuidString).jpg"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try jpeg.write(to: container.appendingPathComponent(relativePath), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return relativePath
        } catch {
            return nil
        }
    }
}

// MARK: - Camera

/// Lets the SwiftUI shutter fire the hidden-controls picker.
@MainActor
final class CameraShutter {
    fileprivate weak var picker: UIImagePickerController?

    func capture() {
        picker?.takePicture()
    }
}

enum CameraAccess: Equatable {
    case available
    case notDetermined
    case denied
    case unavailable

    @MainActor static var current: CameraAccess {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .available
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }
}

struct CameraPreview: UIViewControllerRepresentable {
    let shutter: CameraShutter
    let onImage: @MainActor (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.showsCameraControls = false
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        picker.view.backgroundColor = .black
        shutter.picker = picker
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.onImage = onImage
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage)
    }

    /// No isolation annotation of its own (same choice as `FuelView`'s `DataScannerRepresentable`
    /// coordinator): it only forwards the picked image, hopping explicitly onto the main actor —
    /// UIKit calls these delegate methods on the main thread.
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: @MainActor (UIImage) -> Void

        init(onImage: @escaping @MainActor (UIImage) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else { return }
            nonisolated(unsafe) let captured = image
            let handler = onImage
            MainActor.assumeIsolated {
                handler(captured)
            }
        }
    }
}

// MARK: - Capture stage

/// The capture screen both sheets share.
struct MealPhotoCaptureStage: View {
    let headline: String
    let hint: String
    let onImage: (UIImage) -> Void
    /// Protein only: skip the photo and type the grams in. `nil` hides the button.
    var onManual: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shutter = CameraShutter()
    @State private var cameraAccess: CameraAccess = .current
    @State private var pickerItem: PhotosPickerItem?
    @State private var loadFailed = false
    @State private var isCapturing = false
    @State private var flash = false
    @State private var shutterTick = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.xxs) {
                Text(headline)
                    .font(Theme.Typography.titleLarge)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(hint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.muted)
            }
            .multilineTextAlignment(.center)

            viewfinder

            if loadFailed {
                Text(Copy.fuel.mealPhoto.photoLoadFailedMessage)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            controls
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.lg)
        .sensoryFeedback(.impact(weight: .medium), trigger: shutterTick)
        .task {
            guard cameraAccess == .notDetermined else { return }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAccess = granted ? .available : .denied
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            loadPicked(item)
        }
    }

    // MARK: Viewfinder

    private var viewfinder: some View {
        ZStack {
            Theme.Colors.surface

            switch cameraAccess {
            case .available:
                CameraPreview(shutter: shutter) { image in
                    isCapturing = false
                    onImage(image)
                }
                .accessibilityLabel(Copy.fuel.mealPhoto.framingAccessibilityLabel)
            case .notDetermined:
                SwiftUI.ProgressView().tint(Theme.Colors.muted)
            case .denied, .unavailable:
                unavailableMessage
            }

            if cameraAccess == .available {
                MealPhotoFramingOverlay()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Color.white
                    .opacity(flash ? 0.7 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                .strokeBorder(Theme.Colors.hairline, lineWidth: Theme.Metrics.edgeWidth)
        )
        .frame(maxWidth: .infinity)
    }

    private var unavailableMessage: some View {
        VStack(spacing: Theme.Spacing.md) {
            IconBadge(systemName: cameraAccess == .denied ? "camera.badge.ellipsis" : "camera", tint: Theme.Colors.muted, size: .medium)
            Text(cameraAccess == .denied ? Copy.fuel.mealPhoto.cameraDeniedMessage : Copy.fuel.mealPhoto.cameraUnavailableMessage)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if cameraAccess == .denied, let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Button(Copy.fuel.mealPhoto.openSettingsButton) { openURL(settingsURL) }
                    .font(Theme.Typography.captionEmphasized)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(minHeight: Theme.Metrics.minTapTarget)
            }
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(alignment: .top) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                MealPhotoSideButtonLabel(systemImage: "photo.on.rectangle", title: Copy.fuel.mealPhoto.chooseFromLibraryButton)
            }
            .buttonStyle(PressableStyle(scale: 0.96))
            .frame(maxWidth: .infinity)

            if cameraAccess == .available {
                shutterButton
            }

            Group {
                if let onManual {
                    Button(action: onManual) {
                        MealPhotoSideButtonLabel(systemImage: "square.and.pencil", title: Copy.fuel.mealPhoto.enterManuallyButton)
                    }
                    .buttonStyle(PressableStyle(scale: 0.96))
                } else {
                    Color.clear.frame(width: Theme.Metrics.minTapTarget, height: Theme.Metrics.minTapTarget)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var shutterButton: some View {
        Button {
            guard !isCapturing else { return }
            isCapturing = true
            shutterTick += 1
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.08)) { flash = true }
                withAnimation(.easeIn(duration: 0.25).delay(0.08)) { flash = false }
            }
            shutter.capture()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(Theme.Colors.text, lineWidth: 4)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(Theme.Colors.text)
                    .frame(width: 60, height: 60)
                    .scaleEffect(isCapturing && !reduceMotion ? 0.9 : 1)
            }
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .disabled(isCapturing)
        .accessibilityLabel(Copy.fuel.mealPhoto.shutterAccessibilityLabel)
    }

    private func loadPicked(_ item: PhotosPickerItem) {
        loadFailed = false
        nonisolated(unsafe) let picked = item
        Task {
            let data = try? await picked.loadTransferable(type: Data.self)
            pickerItem = nil
            guard let data, let image = UIImage(data: data) else {
                loadFailed = true
                return
            }
            onImage(image)
        }
    }
}

/// Icon-over-caption label for the two buttons flanking the shutter: a 44pt glass circle so the
/// target is right even though the caption is small.
private struct MealPhotoSideButtonLabel: View {
    let systemImage: String
    let title: String

    var body: some View {
        VStack(spacing: Theme.Spacing.xxs) {
            Image(systemName: systemImage)
                .font(Theme.Typography.icon(.medium))
                .foregroundStyle(Theme.Colors.text)
                .frame(width: Theme.Metrics.minTapTarget + 8, height: Theme.Metrics.minTapTarget + 8)
                .background(ZanoGlass(Circle()))
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

/// Four rounded corner brackets and a soft edge vignette: tells the user "the plate goes here"
/// without covering any of the food.
struct MealPhotoFramingOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let inset = Theme.Spacing.lg
            let arm: CGFloat = 32
            let rect = proxy.frame(in: .local).insetBy(dx: inset, dy: inset)
            ZStack {
                RadialGradient(
                    colors: [.clear, .black.opacity(0.35)],
                    center: .center,
                    startRadius: min(proxy.size.width, proxy.size.height) * 0.35,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.75
                )
                Path { path in
                    // Top-left
                    path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))
                    // Top-right
                    path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
                    // Bottom-right
                    path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
                    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
                    // Bottom-left
                    path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
                }
                .stroke(Theme.Colors.text.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Working / message states

/// The photo, dimmed, under a spinner and a one-line status ("Estimating protein…").
struct MealPhotoWorkingView: View {
    let image: UIImage?
    let caption: String

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .overlay(Theme.Colors.background.opacity(0.55))
                } else {
                    Theme.Colors.surface
                }
                SwiftUI.ProgressView()
                    .controlSize(.large)
                    .tint(Theme.Colors.text)
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            Text(caption)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.text)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .accessibilityElement(children: .combine)
        .onAppear { AccessibilityNotification.Announcement(caption).post() }
    }
}

/// Icon, title, message, then the caller's buttons pinned to the bottom.
struct MealPhotoMessageView<Actions: View>: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            VStack(spacing: Theme.Spacing.md) {
                IconBadge(systemName: systemImage, tint: tint, size: .large)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            VStack(spacing: Theme.Spacing.sm) {
                actions()
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { AccessibilityNotification.Announcement("\(title). \(message)").post() }
    }
}

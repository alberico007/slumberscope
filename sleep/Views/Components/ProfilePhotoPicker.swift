//
//  ProfilePhotoPicker.swift
//  sleep
//

import PhotosUI
import SwiftUI
import UIKit

/// Circular profile-photo picker. Taps open the system Photos picker, then
/// center-crops the selection to a square and stores it as JPEG bytes in
/// the bound `photoData`. Used on the onboarding profile page and in the
/// Settings profile view so the user's face can appear in PDF exports sent
/// to a clinician.
struct ProfilePhotoPicker: View {

    @Binding var photoData: Data?
    var size: CGFloat = 110
    var initials: String = ""

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        let currentPhoto = photoData
        return PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color.cyan.opacity(0.25), Color.blue.opacity(0.15)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: size, height: size)

                if let data = currentPhoto, let uiImage = UIImage(data: data) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else if !initials.isEmpty {
                    Text(initials.uppercased())
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: size * 0.85))
                        .foregroundStyle(.cyan)
                }

                // Camera badge in the bottom-right
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: size * 0.32, height: size * 0.32)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: size * 0.14, weight: .semibold))
                            .foregroundStyle(.cyan)
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
                    .offset(x: size * 0.35, y: size * 0.35)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let cropped = Self.centerSquareJPEG(data: data, maxSide: 512) {
                    await MainActor.run {
                        photoData = cropped
                    }
                }
            }
        }
    }

    /// Loads UIImage from data, center-crops to the largest square, resizes
    /// so the longest side is at most `maxSide`, and re-encodes as JPEG at
    /// 0.85 quality. Result sits well under 200 KB for typical camera photos.
    static func centerSquareJPEG(data: Data, maxSide: CGFloat) -> Data? {
        guard let original = UIImage(data: data) else { return nil }
        let side = min(original.size.width, original.size.height)
        let originX = (original.size.width - side) / 2
        let originY = (original.size.height - side) / 2
        let cropRect = CGRect(x: originX, y: originY, width: side, height: side)
        guard let cgImage = original.cgImage?.cropping(to: cropRect) else { return nil }
        let cropped = UIImage(cgImage: cgImage, scale: original.scale, orientation: original.imageOrientation)

        let targetSide = min(maxSide, cropped.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetSide, height: targetSide), format: format)
        let resized = renderer.image { _ in
            cropped.draw(in: CGRect(x: 0, y: 0, width: targetSide, height: targetSide))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

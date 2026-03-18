//
//  Extensions.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//

import Foundation
import UIKit

extension Collection {
    subscript(safe index: Index) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

extension UIImage {
    func croppedToSquare() -> UIImage {
        let side = min(size.width, size.height)
        let origin = CGPoint(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2
        )
        let cropRect = CGRect(origin: origin, size: CGSize(width: side, height: side))
        guard let cgImage = cgImage?.cropping(to: cropRect) else { return self }
        return UIImage(cgImage: cgImage, scale: scale, orientation: imageOrientation)
    }
}

final class PhotoSaveHelper: NSObject {
    private let outpaint: (Error?) -> Void
    
    init(outpaint: @escaping (Error?) -> Void) {
        self.outpaint = outpaint
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        outpaint(error)
    }
}

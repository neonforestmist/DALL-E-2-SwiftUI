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

final class PhotoSaveHelper: NSObject {
    private let outpaint: (Error?) -> Void
    
    init(outpaint: @escaping (Error?) -> Void) {
        self.outpaint = outpaint
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        outpaint(error)
    }
}

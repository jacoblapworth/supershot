#if DEBUG
import SwiftUI

#if os(iOS)
import UIKit

struct DatabaseShareSheet: UIViewControllerRepresentable {
  let url: URL
  var completion: (Result<Void, any Error>) -> Void

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(
      activityItems: [url], applicationActivities: nil
    )
    controller.completionWithItemsHandler = { _, _, _, error in
      if let error {
        completion(.failure(error))
      } else {
        completion(.success(()))
      }
    }
    return controller
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
import AppKit

struct DatabaseShareSheet: NSViewRepresentable {
  let url: URL
  var completion: (Result<Void, any Error>) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(completion: completion)
  }

  func makeNSView(context: Context) -> NSView {
    NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
  }

  func updateNSView(_ view: NSView, context: Context) {
    guard context.coordinator.picker == nil else { return }
    let picker = NSSharingServicePicker(items: [url])
    picker.delegate = context.coordinator
    context.coordinator.picker = picker
    DispatchQueue.main.async {
      picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
  }

  final class Coordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    var picker: NSSharingServicePicker?
    let completion: (Result<Void, any Error>) -> Void

    init(completion: @escaping (Result<Void, any Error>) -> Void) {
      self.completion = completion
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
      if service == nil { completion(.success(())) }
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
      self
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
      completion(.success(()))
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
      completion(.failure(error))
    }
  }
}
#endif
#endif

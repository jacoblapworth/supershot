import AppSettings
import Database
import GameCore
import PaywallFeature
import SharedModels
import Styleguide
import SubscriptionClient

#if DEBUG
  import SwiftUI

  #if os(iOS)
    import UIKit

    package struct DatabaseShareSheet: UIViewControllerRepresentable {
      package let url: URL
      package var completion: (Result<Void, any Error>) -> Void

      package func makeUIViewController(context: Context) -> UIActivityViewController {
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

      package func updateUIViewController(_ controller: UIActivityViewController, context: Context)
      {}

      package init(url: URL, completion: @escaping (Result<Void, any Error>) -> Void) {
        self.url = url
        self.completion = completion
      }
    }
  #elseif os(macOS)
    import AppKit

    package struct DatabaseShareSheet: NSViewRepresentable {
      package let url: URL
      package var completion: (Result<Void, any Error>) -> Void

      package func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
      }

      package func makeNSView(context: Context) -> NSView {
        NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
      }

      package func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.picker == nil else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.delegate = context.coordinator
        context.coordinator.picker = picker
        DispatchQueue.main.async {
          picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
      }

      final package class Coordinator: NSObject, NSSharingServicePickerDelegate,
        NSSharingServiceDelegate
      {
        package var picker: NSSharingServicePicker?
        package let completion: (Result<Void, any Error>) -> Void

        package init(completion: @escaping (Result<Void, any Error>) -> Void) {
          self.completion = completion
        }

        package func sharingServicePicker(
          _ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?
        ) {
          if service == nil { completion(.success(())) }
        }

        package func sharingServicePicker(
          _ sharingServicePicker: NSSharingServicePicker,
          delegateFor sharingService: NSSharingService
        ) -> (any NSSharingServiceDelegate)? {
          self
        }

        package func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any])
        {
          completion(.success(()))
        }

        package func sharingService(
          _ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error
        ) {
          completion(.failure(error))
        }
      }

      package init(url: URL, completion: @escaping (Result<Void, any Error>) -> Void) {
        self.url = url
        self.completion = completion
      }
    }
  #endif
#endif

import UIKit
import SwiftUI
import Contacts
import ContactsUI

class ContactAccessViewController: UIViewController {
    private var searchText: String = ""
    private var onContactsSelected: (([String]) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupContactAccessView()
    }
    
    func configure(searchText: String, onContactsSelected: @escaping ([String]) -> Void) {
        self.searchText = searchText
        self.onContactsSelected = onContactsSelected
    }
    
    private func setupContactAccessView() {
        let contactAccessView = ContactAccessView(
            searchText: searchText,
            onContactsSelected: onContactsSelected ?? { _ in }
        )
        
        let hostingController = UIHostingController(rootView: contactAccessView)
        addChild(hostingController)
        view.addSubview(hostingController.view)
        
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        hostingController.didMove(toParent: self)
    }
}

struct ContactAccessView: View {
    let searchText: String
    let onContactsSelected: ([String]) -> Void
    
    @State private var authorizationStatus: CNAuthorizationStatus = .notDetermined
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Contact Access")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Search for contacts to add to Assiist")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if authorizationStatus == .limited || authorizationStatus == .notDetermined {
                ContactAccessButton(queryString: searchText) { identifiers in
                    onContactsSelected(identifiers)
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .contactAccessButtonCaption(.phone)
                .contactAccessButtonStyle(ContactAccessButton.Style(imageWidth: 40))
                .padding()
            } else if authorizationStatus == .authorized {
                Text("You have full access to contacts")
                    .font(.body)
                    .foregroundColor(.green)
            } else {
                VStack(spacing: 16) {
                    Text("Contact access is required")
                        .font(.body)
                        .foregroundColor(.red)
                    
                    Button("Open Settings") {
                        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsUrl)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Spacer()
        }
        .padding()
        .onAppear {
            authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
        }
    }
} 
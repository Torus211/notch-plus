//
//  TabButton.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-24.
//

import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(label).font(.system(size: 11, weight: .medium))
            }
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}

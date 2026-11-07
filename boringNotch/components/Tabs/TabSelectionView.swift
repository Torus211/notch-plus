//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import SwiftUI
import Defaults

struct TabModel: Identifiable {
    var id: String { view.rawValue }
    let label: String
    let icon: String
    let view: NotchViews
}

let tabs = [
    TabModel(label: "Музыка", icon: "music.note", view: .home),
    TabModel(label: "Полка", icon: "tray.fill", view: .shelf),
    TabModel(label: "Календарь", icon: "calendar", view: .calendar),
    TabModel(label: "Буфер", icon: "doc.on.clipboard", view: .clipboard),
    TabModel(label: "Погода", icon: "cloud.sun.fill", view: .weather),
    TabModel(label: "Устройства", icon: "headphones", view: .devices)
]

@MainActor
var configuredFeatureTabs: [TabModel] {
    tabs
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(configuredFeatureTabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                        if tab.view != .weather && tab.view != .clipboard {
                            NSApp.keyWindow?.resignKey()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .foregroundStyle(tab.view == coordinator.currentView ? Color.accentColor : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color.accentColor.opacity(0.16) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color.accentColor.opacity(0.16) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .padding(3)
        .background(.white.opacity(0.045), in: Capsule())
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}

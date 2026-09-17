//
//  SoundiscoAppApp.swift
//  SoundiscoApp
//
//  Created by ramon.  on 9/14/26.
//

import SwiftUI

@main
struct SoundiscoAppApp: App {
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var notificationDelegate
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

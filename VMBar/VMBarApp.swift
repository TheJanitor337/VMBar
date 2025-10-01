//
//  VMBarApp.swift
//  VMBar
//
//  Created by TJW on 9/24/25.
//

import SwiftUI

@main
struct VMBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

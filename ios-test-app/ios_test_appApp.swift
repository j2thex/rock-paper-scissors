//
//  ios_test_appApp.swift
//  ios-test-app
//
//  Created by Jeffrey Smith on 3/11/24.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth
import os.log

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // Suppress specific warnings
        UserDefaults.standard.set(false, forKey: "_UIConstraintBasedLayoutLogUnsatisfiable")
        
        // Redirect STDERR to /dev/null for gRPC warnings
        if let stderrPath = strdup("/dev/null"),
           let stream = fopen(stderrPath, "w") {
            dup2(fileno(stream), STDERR_FILENO)
            free(stderrPath)
        }
        
        // Configure Firebase
        print("Starting Firebase configuration...")
        
        // Check if GoogleService-Info.plist exists and print its contents
        if let filePath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plistDict = NSDictionary(contentsOfFile: filePath) {
            print("📱 Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
            print("🔥 Firebase Project ID: \(plistDict["PROJECT_ID"] ?? "not found")")
        } else {
            print("❌ GoogleService-Info.plist not found or invalid")
            return false
        }
        
        // Configure Firebase
        FirebaseApp.configure()
        
        // Verify configuration
        if let projectID = FirebaseApp.app()?.options.projectID {
            print("✅ Firebase configured with project: \(projectID)")
        } else {
            print("❌ Firebase configuration failed")
            return false
        }
        
        return true
    }
    
    // Add this to suppress additional warnings
    func application(_ application: UIApplication,
                    didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.noData)
    }
}

@main
struct ios_test_appApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    init() {
        // Suppress CKBrowserSwitcherViewController warning
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.set(false, forKey: "\(bundleID).CKBrowserSwitcherViewController.override")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

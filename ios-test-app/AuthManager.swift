import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Network

class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var error: String?
    
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    @Published var isConnected = true
    
    // Add this property to store the auth state listener
    private var authStateHandler: AuthStateDidChangeListenerHandle?
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
            }
        }
        monitor.start(queue: queue)
        
        // Store the listener handle
        authStateHandler = auth.addStateDidChangeListener { [weak self] _, user in
            if let userId = user?.uid {
                self?.isAuthenticated = true
                self?.fetchUserData(userId: userId)
            } else {
                self?.isAuthenticated = false
                self?.currentUser = nil
            }
        }
    }
    
    private func checkConnection() -> Bool {
        guard isConnected else {
            self.error = "No internet connection. Please check your network settings."
            return false
        }
        return true
    }
    
    func signIn(email: String, password: String) {
        guard checkConnection() else { return }
        isLoading = true
        error = nil // Clear previous errors
        
        auth.signIn(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                if let error = error {
                    print("Sign in error: \(error.localizedDescription)")
                    self?.error = error.localizedDescription
                }
            }
        }
    }
    
    func signUp(email: String, password: String, name: String) {
        guard checkConnection() else { return }
        isLoading = true
        error = nil
        
        print("Starting sign up process...")
        print("Email validation: \(email.contains("@") && email.contains("."))")
        print("Password validation: \(password.count >= 6)")
        
        // Basic validation
        guard email.contains("@"), email.contains(".") else {
            self.error = "Please enter a valid email address"
            self.isLoading = false
            return
        }
        
        guard password.count >= 6 else {
            self.error = "Password must be at least 6 characters"
            self.isLoading = false
            return
        }
        
        guard !name.isEmpty else {
            self.error = "Please enter your name"
            self.isLoading = false
            return
        }
        
        // Try to create user
        auth.createUser(withEmail: email, password: password) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    print("❌ Firebase Auth Error: \(error.code)")
                    print("Error Domain: \(error.domain)")
                    print("Error Description: \(error.localizedDescription)")
                    print("Error User Info: \(error.userInfo)")
                    
                    // Provide user-friendly error messages
                    switch error.code {
                    case AuthErrorCode.emailAlreadyInUse.rawValue:
                        self?.error = "This email is already registered"
                    case AuthErrorCode.invalidEmail.rawValue:
                        self?.error = "Please enter a valid email address"
                    case AuthErrorCode.weakPassword.rawValue:
                        self?.error = "Please choose a stronger password"
                    default:
                        self?.error = "Sign up failed: \(error.localizedDescription)"
                    }
                    self?.isLoading = false
                    return
                }
                
                guard let userId = result?.user.uid else {
                    self?.error = "Failed to get user ID"
                    self?.isLoading = false
                    return
                }
                
                print("✅ User created successfully with ID: \(userId)")
                
                let newUser = User(
                    id: userId,
                    name: name,
                    wins: 0,
                    losses: 0,
                    draws: 0
                )
                
                self?.createUserDocument(user: newUser)
            }
        }
    }
    
    private func createUserDocument(user: User) {
        print("Creating user document for ID: \(user.id)")
        
        let userData: [String: Any] = [
            "name": user.name,
            "wins": user.wins,
            "losses": user.losses,
            "draws": user.draws,
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        // First try to create the document
        db.collection("users").document(user.id).setData(userData, merge: true) { [weak self] error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Firestore error: \(error.localizedDescription)")
                    self?.error = "Failed to save user data: \(error.localizedDescription)"
                    self?.isLoading = false
                } else {
                    print("User document created successfully")
                    self?.currentUser = user
                    self?.isAuthenticated = true
                    self?.isLoading = false
                    
                    // After successful creation, try to fetch the document
                    self?.fetchUserData(userId: user.id)
                }
            }
        }
    }
    
    func signOut() {
        do {
            try auth.signOut()
            isAuthenticated = false
            currentUser = nil
        } catch let error {
            print("Sign out error: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }
    
    private func fetchUserData(userId: String) {
        print("Fetching user data for ID: \(userId)")
        
        // Add retry mechanism
        let maxRetries = 3
        var currentRetry = 0
        
        func tryFetch() {
            db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
                if let error = error {
                    print("Fetch user error: \(error.localizedDescription)")
                    if currentRetry < maxRetries {
                        currentRetry += 1
                        print("Retrying fetch... Attempt \(currentRetry)")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            tryFetch()
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.error = "Failed to fetch user data: \(error.localizedDescription)"
                        }
                    }
                    return
                }
                
                guard let data = snapshot?.data() else {
                    print("No user data found")
                    return
                }
                
                DispatchQueue.main.async {
                    let name = data["name"] as? String ?? ""
                    let wins = data["wins"] as? Int ?? 0
                    let losses = data["losses"] as? Int ?? 0
                    let draws = data["draws"] as? Int ?? 0
                    
                    self?.currentUser = User(
                        id: userId,
                        name: name,
                        wins: wins,
                        losses: losses,
                        draws: draws
                    )
                    print("User data fetched successfully")
                }
            }
        }
        
        tryFetch()
    }
    
    func updateGameResult(result: GameResult) {
        guard let userId = auth.currentUser?.uid else {
            print("No authenticated user found")
            return
        }
        
        print("Updating game result for user: \(userId)")
        
        // First, check if the document exists
        db.collection("users").document(userId).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("Error checking document: \(error.localizedDescription)")
                return
            }
            
            if let snapshot = snapshot, snapshot.exists {
                // Document exists, update it
                let update: [String: Any]
                switch result {
                case .win:
                    update = ["wins": FieldValue.increment(Int64(1))]
                case .lose:
                    update = ["losses": FieldValue.increment(Int64(1))]
                case .draw:
                    update = ["draws": FieldValue.increment(Int64(1))]
                case .none:
                    return
                }
                
                self?.db.collection("users").document(userId).updateData(update) { error in
                    if let error = error {
                        print("Update game result error: \(error.localizedDescription)")
                        self?.error = "Failed to update game result"
                    } else {
                        print("Game result updated successfully")
                        self?.fetchUserData(userId: userId)
                    }
                }
            } else {
                // Document doesn't exist, create it
                print("Creating new user document for game result")
                var initialData: [String: Any] = [
                    "name": "Player",  // Default name
                    "wins": 0,
                    "losses": 0,
                    "draws": 0,
                    "createdAt": FieldValue.serverTimestamp()
                ]
                
                // Update the appropriate counter
                switch result {
                case .win:
                    initialData["wins"] = 1
                case .lose:
                    initialData["losses"] = 1
                case .draw:
                    initialData["draws"] = 1
                case .none:
                    break
                }
                
                self?.db.collection("users").document(userId).setData(initialData) { error in
                    if let error = error {
                        print("Create user document error: \(error.localizedDescription)")
                        self?.error = "Failed to create user document"
                    } else {
                        print("User document created with initial game result")
                        self?.fetchUserData(userId: userId)
                    }
                }
            }
        }
    }
    
    deinit {
        // Remove both listeners
        monitor.cancel()
        if let handler = authStateHandler {
            auth.removeStateDidChangeListener(handler)
        }
    }
} 
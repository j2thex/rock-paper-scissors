//
//  ContentView.swift
//  ios-test-app
//
//  Created by Jeffrey Smith on 3/11/24.
//

import SwiftUI
import CoreLocation
import CoreMotion
import AVFoundation
import CoreImage.CIFilterBuiltins
import FirebaseAuth
import FirebaseFirestore

// Game States to manage flow
enum GameState {
    case scanning
    case waitingForOpponent
    case playing
    case finished
    case practicing  // New state for practice mode
}

// Basic game moves
enum GameMove: String, CaseIterable {
    case rock = "🪨"
    case paper = "📄"
    case scissors = "✂️"
    
    var description: String {
        switch self {
        case .rock: return "Rock"
        case .paper: return "Paper"
        case .scissors: return "Scissors"
        }
    }
}

// Game results
enum GameResult {
    case win
    case lose
    case draw
    case none
    
    var description: String {
        switch self {
        case .win: return "You Won! 🎉"
        case .lose: return "You Lost! 😢"
        case .draw: return "It's a Draw! 🤝"
        case .none: return ""
        }
    }
}

// Main game manager
class GameManager: ObservableObject {
    @Published var gameState: GameState = .scanning
    @Published var opponentID: String?
    @Published var selectedMove: GameMove?
    @Published var computerMove: GameMove?
    @Published var shakeCount = 0
    @Published var showScanner = false
    @Published var gameResult: GameResult = .none
    
    private let motionManager = CMMotionManager()
    private var lastShakeTime: Date?
    
    var authManager: AuthManager?
    
    var playerID: String {
        return Auth.auth().currentUser?.uid ?? ""
    }
    
    func startShakeDetection() {
        guard motionManager.isAccelerometerAvailable else {
            print("Accelerometer not available")
            return
        }
        
        // Reset shake count when starting detection
        shakeCount = 0
        lastShakeTime = nil
        
        motionManager.accelerometerUpdateInterval = 0.01
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self,
                  let data = data else { return }
            
            // Only process shakes if a move is selected
            guard self.selectedMove != nil else { return }
            
            let acceleration = sqrt(
                pow(data.acceleration.x, 2) +
                pow(data.acceleration.y, 2) +
                pow(data.acceleration.z, 2)
            ) - 1.0
            
            let threshold = 0.7
            let now = Date()
            
            if acceleration > threshold {
                if let lastShake = self.lastShakeTime {
                    let timeSinceLastShake = now.timeIntervalSince(lastShake)
                    if timeSinceLastShake < 0.3 {
                        return
                    }
                }
                
                self.lastShakeTime = now
                DispatchQueue.main.async {
                    if self.shakeCount < 3 {
                        self.shakeCount += 1
                        
                        // Haptic feedback
                        let generator = UIImpactFeedbackGenerator(style: .heavy)
                        generator.impactOccurred()
                        
                        // Sound feedback
                        AudioServicesPlaySystemSound(1519)
                        
                        if self.shakeCount == 3 {
                            self.determineWinner()
                        }
                    }
                }
            }
        }
    }
    
    func stopShakeDetection() {
        motionManager.stopAccelerometerUpdates()
    }
    
    func resetGame() {
        stopShakeDetection()  // Stop current shake detection
        gameState = .scanning
        opponentID = nil
        selectedMove = nil
        computerMove = nil
        shakeCount = 0
        gameResult = .none
    }
    
    func startPracticeMode() {
        gameState = .practicing
        selectedMove = nil
        computerMove = nil
        shakeCount = 0
        gameResult = .none
    }
    
    func determineWinner() {
        print("Determining winner...")
        print("Selected move: \(selectedMove?.description ?? "none")")  // Debug print
        
        // Ensure we have a selected move
        guard let playerMove = selectedMove else {
            print("No player move selected")
            return
        }
        
        if gameState == .practicing {
            // Generate computer's move
            computerMove = GameMove.allCases.randomElement()
            guard let computerMove = computerMove else { 
                print("Failed to generate computer move")
                return 
            }
            
            print("Player move: \(playerMove.description)")
            print("Computer move: \(computerMove.description)")
            
            // Calculate and set result
            gameResult = calculateResult(player: playerMove, opponent: computerMove)
            print("Game result: \(gameResult.description)")
            
            // Set game state to finished
            DispatchQueue.main.async {
                self.gameState = .finished
            }
        }
        
        authManager?.updateGameResult(result: gameResult)
    }
    
    private func calculateResult(player: GameMove, opponent: GameMove) -> GameResult {
        if player == opponent { return .draw }
        
        switch (player, opponent) {
        case (.rock, .scissors),
             (.paper, .rock),
             (.scissors, .paper):
            return .win
        default:
            return .lose
        }
    }
    
    func startGame() {
        startShakeDetection()
    }
    
    // Update the rematch function in GameManager
    func rematch() {
        if gameState == .practicing || gameState == .finished {
            // Reset all game state
            selectedMove = nil
            computerMove = nil
            shakeCount = 0
            gameResult = .none
            
            // Set state to practicing and start new game
            DispatchQueue.main.async {
                self.gameState = .practicing
                self.startShakeDetection()  // Restart shake detection
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var authManager = AuthManager()
    
    var body: some View {
        Group {
            if authManager.isAuthenticated {
                GameView(authManager: authManager)
            } else {
                AuthView()
            }
        }
    }
}

struct GameView: View {
    @ObservedObject var authManager: AuthManager
    @StateObject private var gameManager = GameManager()
    @State private var showQRCode = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // User Stats
                if let user = authManager.currentUser {
                    UserStatsView(user: user)
                }
                
                // Main Game Area
                Group {
                    switch gameManager.gameState {
                    case .scanning:
                        VStack {
                            ScanningView(gameManager: gameManager)
                            
                            // Practice Mode Button
                            Button(action: {
                                gameManager.startPracticeMode()
                            }) {
                                Label("Practice Mode", systemImage: "person.fill")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(Color.green)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                        }
                    case .practicing:
                        GamePlayView(gameManager: gameManager)
                    case .waitingForOpponent:
                        WaitingView()
                    case .playing:
                        GamePlayView(gameManager: gameManager)
                    case .finished:
                        GameResultView(gameManager: gameManager)
                    }
                }
                .frame(maxHeight: .infinity)
                
                // Action Buttons (hide during practice mode)
                if gameManager.gameState == .scanning {
                    HStack(spacing: 20) {
                        Button(action: { showQRCode = true }) {
                            Label("Show QR", systemImage: "qrcode")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: { gameManager.showScanner = true }) {
                            Label("Scan QR", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.large)
                    .padding(.horizontal)
                }
            }
            .navigationTitle("Rock Paper Scissors")
            .navigationBarItems(trailing: Button("Sign Out") {
                authManager.signOut()
            })
            .sheet(isPresented: $showQRCode) {
                QRCodeView(playerID: gameManager.playerID)
            }
            .sheet(isPresented: $gameManager.showScanner) {
                QRScannerView { scannedCode in
                    gameManager.opponentID = scannedCode
                    gameManager.gameState = .playing
                }
            }
            .onAppear {
                // Connect the managers
                gameManager.authManager = authManager
            }
        }
        .navigationViewStyle(.stack)
    }
}

struct UserStatsView: View {
    let user: User
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Player: \(user.name)")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatItem(label: "Wins", value: user.wins)
                StatItem(label: "Losses", value: user.losses)
                StatItem(label: "Win Rate", value: String(format: "%.1f%%", user.winRate))
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(Color.secondary.opacity(0.1)))
    }
}

struct StatItem: View {
    let label: String
    let value: Any
    
    var body: some View {
        VStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(value)")
                .font(.headline)
        }
    }
}

struct AuthView: View {
    @StateObject private var authManager = AuthManager()
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var isSignUp = false
    @FocusState private var focusedField: Field?
    
    enum Field {
        case name, email, password
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 25) {
                        // Logo or App Icon
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                            .padding(.top, 40)
                        
                        Text(isSignUp ? "Create Account" : "Welcome Back")
                            .font(.title)
                            .bold()
                        
                        VStack(spacing: 16) {
                            if isSignUp {
                                TextField("Name", text: $name)
                                    .textFieldStyle(AuthTextFieldStyle())
                                    .focused($focusedField, equals: .name)
                                    .submitLabel(.next)
                            }
                            
                            TextField("Email", text: $email)
                                .textFieldStyle(AuthTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                            
                            SecureField("Password", text: $password)
                                .textFieldStyle(AuthTextFieldStyle())
                                .focused($focusedField, equals: .password)
                                .submitLabel(.done)
                        }
                        .padding(.horizontal)
                        
                        if authManager.isLoading {
                            ProgressView()
                                .padding()
                        } else {
                            Button(action: {
                                hideKeyboard()
                                if isSignUp {
                                    authManager.signUp(email: email,
                                                    password: password,
                                                    name: name)
                                } else {
                                    authManager.signIn(email: email,
                                                    password: password)
                                }
                            }) {
                                Text(isSignUp ? "Sign Up" : "Sign In")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                            .disabled(email.isEmpty || password.isEmpty || (isSignUp && name.isEmpty))
                        }
                        
                        Button(action: { 
                            withAnimation {
                                isSignUp.toggle()
                                email = ""
                                password = ""
                                name = ""
                                focusedField = nil
                            }
                        }) {
                            Text(isSignUp ? "Already have an account? Sign In" :
                                          "Don't have an account? Sign Up")
                                .foregroundColor(.blue)
                        }
                        
                        if let error = authManager.error {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
            .navigationBarHidden(true)
            .adaptiveKeyboard()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                      to: nil, from: nil, for: nil)
    }
}

// Add this custom text field style
struct AuthTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
            )
            .cornerRadius(8)
    }
}

// Add these placeholder views - I can provide full implementations if needed
struct QRCodeView: View {
    let playerID: String
    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage?
    @State private var userName: String = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Your QR Code")
                    .font(.headline)
                
                if !userName.isEmpty {
                    Text(userName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // QR Code Image
                Group {
                    if let qrImage = qrImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 250, height: 250)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(radius: 5)
                    } else {
                        ProgressView()
                            .frame(width: 250, height: 250)
                    }
                }
                
                Text("Show this to your opponent")
                    .foregroundColor(.secondary)
                
                Text(playerID)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .padding()
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
            .onAppear {
                // Get user name
                if let user = Auth.auth().currentUser {
                    Firestore.firestore().collection("users").document(user.uid).getDocument { snapshot, error in
                        if let data = snapshot?.data(),
                           let name = data["name"] as? String {
                            userName = name
                        }
                    }
                }
                
                // Generate QR code
                DispatchQueue.global(qos: .userInitiated).async {
                    let generatedImage = generateQRCode(from: playerID)
                    DispatchQueue.main.async {
                        self.qrImage = generatedImage
                    }
                }
            }
        }
    }
    
    private func generateQRCode(from string: String) -> UIImage? {
        let data = Data(string.utf8)
        let filter = CIFilter.qrCodeGenerator()
        
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Use UIGraphicsImageRenderer instead of CIContext
        let scale = UIScreen.main.scale
        let size = CGSize(width: 250 * scale, height: 250 * scale)
        
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)
            context.cgContext.interpolationQuality = .none
            
            // Calculate scale transform
            let scaleX = size.width / outputImage.extent.width
            let scaleY = size.height / outputImage.extent.height
            let transformedImage = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            if let cgImage = CIContext().createCGImage(transformedImage, from: transformedImage.extent) {
                context.cgContext.draw(cgImage, in: bounds)
            }
        }
    }
}

// Add QRScannerController for camera handling
class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onCodeScanned: (String) -> Void
    
    init(onCodeScanned: @escaping (String) -> Void) {
        self.onCodeScanned = onCodeScanned
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if let captureSession = captureSession, !captureSession.isRunning {
            captureSession.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let captureSession = captureSession, captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    private func setupCamera() {
        let captureSession = AVCaptureSession()
        self.captureSession = captureSession
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            }
            
            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) {
                captureSession.addOutput(metadataOutput)
                
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            }
            
            // Setup preview layer
            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer
            
            // Add scanning frame
            let scanFrame = UIView()
            scanFrame.layer.borderColor = UIColor.green.cgColor
            scanFrame.layer.borderWidth = 2
            scanFrame.frame = CGRect(x: view.bounds.midX - 100,
                                   y: view.bounds.midY - 100,
                                   width: 200,
                                   height: 200)
            view.addSubview(scanFrame)
            
            // Start capturing
            DispatchQueue.global(qos: .background).async {
                captureSession.startRunning()
            }
            
        } catch {
            print("Camera setup error: \(error)")
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                       didOutput metadataObjects: [AVMetadataObject],
                       from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
           let stringValue = metadataObject.stringValue {
            captureSession?.stopRunning()
            onCodeScanned(stringValue)
        }
    }
}

// Update QRScannerView to use the controller
struct QRScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            QRScannerViewControllerRepresentable(onCodeScanned: { code in
                onScan(code)
                dismiss()
            })
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
            .navigationTitle("Scan QR Code")
            .ignoresSafeArea(.all, edges: .bottom)
        }
    }
}

// Add UIViewControllerRepresentable for the scanner
struct QRScannerViewControllerRepresentable: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerController {
        return QRScannerController(onCodeScanned: onCodeScanned)
    }
    
    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}
}

struct WaitingView: View {
    var body: some View {
        ProgressView("Waiting for opponent...")
    }
}

struct GameResultView: View {
    @ObservedObject var gameManager: GameManager
    
    var body: some View {
        VStack(spacing: 25) {
            ScrollView {
                VStack(spacing: 25) {
                    Text(gameManager.gameResult.description)
                        .font(.title)
                        .bold()
                    
                    // Show the moves with large emojis
                    HStack(spacing: 30) {
                        if let playerMove = gameManager.selectedMove {
                            VStack(spacing: 12) {
                                Text("You chose")
                                    .font(.headline)
                                Text(playerMove.rawValue)
                                    .font(.system(size: 80))
                                Text(playerMove.description)
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.blue.opacity(0.1))
                            )
                        }
                        
                        Text("VS")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        if let computerMove = gameManager.computerMove {
                            VStack(spacing: 12) {
                                Text("Opponent chose")
                                    .font(.headline)
                                Text(computerMove.rawValue)
                                    .font(.system(size: 80))
                                Text(computerMove.description)
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.red.opacity(0.1))
                            )
                        }
                    }
                    .padding(.vertical)
                    
                    // Result indicator
                    HStack {
                        Image(systemName: gameManager.gameResult == .win ? "trophy.fill" : 
                                       gameManager.gameResult == .lose ? "xmark.circle.fill" : 
                                       "equal.circle.fill")
                            .font(.title)
                            .foregroundColor(gameManager.gameResult == .win ? .yellow :
                                           gameManager.gameResult == .lose ? .red :
                                           .blue)
                        Text(gameManager.gameResult == .win ? "Victory!" :
                             gameManager.gameResult == .lose ? "Defeat!" :
                             "Draw!")
                            .font(.title2)
                            .bold()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.1))
                    )
                }
            }
            
            // Action buttons at bottom
            VStack(spacing: 15) {
                Button(action: {
                    gameManager.rematch()
                }) {
                    Label("Play Again", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue)
                        .cornerRadius(12)
                }
                
                Button(action: {
                    gameManager.resetGame()
                }) {
                    Label("Main Menu", systemImage: "house.fill")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                }
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

// Add this struct after GameResultView
struct ScanningView: View {
    @ObservedObject var gameManager: GameManager
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 100))
                .foregroundColor(.blue.opacity(0.5))
            
            Text("Start by either showing your QR code\nor scanning your opponent's code")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(spacing: 12) {
                Text("How to play:")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Label("Show your QR code to opponent", systemImage: "1.circle.fill")
                    Label("Scan opponent's QR code", systemImage: "2.circle.fill")
                    Label("Choose your move", systemImage: "3.circle.fill")
                    Label("Shake phone 3 times", systemImage: "4.circle.fill")
                }
                .font(.subheadline)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.1)))
        }
        .padding()
    }
}

// Add GamePlayView
struct GamePlayView: View {
    @ObservedObject var gameManager: GameManager
    
    var body: some View {
        VStack(spacing: 20) {
            if gameManager.gameState == .practicing {
                Text("Practice Mode")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            
            // Move Selection
            HStack(spacing: 20) {
                ForEach(GameMove.allCases, id: \.self) { move in
                    Button(action: {
                        gameManager.selectedMove = move
                    }) {
                        VStack {
                            Text(move.rawValue)
                                .font(.system(size: 50))
                            Text(move.description)
                                .font(.caption)
                        }
                        .frame(width: 100, height: 100)
                        .background(gameManager.selectedMove == move ? 
                                  Color.blue.opacity(0.3) : 
                                  Color.secondary.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
            }
            
            if let selectedMove = gameManager.selectedMove {
                // Show selected move
                Text("Selected: \(selectedMove.description)")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                // Shake Instructions
                VStack {
                    Text("Shake phone \(gameManager.shakeCount)/3 times!")
                        .font(.headline)
                        .foregroundColor(.green)
                    
                    ProgressView(value: Double(gameManager.shakeCount),
                               total: 3)
                        .tint(.blue)
                        .scaleEffect(1.5)
                        .padding(.top)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.secondary.opacity(0.1))
                )
                .padding()
            }
        }
        .onAppear {
            gameManager.startShakeDetection()
        }
        .onDisappear {
            gameManager.stopShakeDetection()
        }
    }
}

#Preview {
    ContentView()
}

struct AdaptiveKeyboardModifier: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .offset(y: -min(keyboardHeight * 0.5, geometry.size.height * 0.3))
                .animation(.easeOut(duration: 0.16), value: keyboardHeight)
                .onAppear {
                    setupKeyboardNotifications()
                }
                .onDisappear {
                    removeKeyboardNotifications()
                }
        }
    }
    
    private func setupKeyboardNotifications() {
        let notificationCenter = NotificationCenter.default
        
        notificationCenter.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                return
            }
            keyboardHeight = keyboardFrame.height
        }
        
        notificationCenter.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            keyboardHeight = 0
        }
    }
    
    private func removeKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
}

// Add this extension at the bottom of the file
extension View {
    func adaptiveKeyboard() -> some View {
        self.modifier(AdaptiveKeyboardModifier())
    }
}

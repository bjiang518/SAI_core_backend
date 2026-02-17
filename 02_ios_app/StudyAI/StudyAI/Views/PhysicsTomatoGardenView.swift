//
//  PhysicsTomatoGardenView.swift
//  StudyAI
//
//  物理番茄园 - 番茄会随着手机晃动而移动
//

import SwiftUI
import SpriteKit
import CoreMotion

// MARK: - SwiftUI Wrapper View
struct PhysicsTomatoGardenView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var gardenService = TomatoGardenService.shared

    var body: some View {
        ZStack {
            // SpriteKit Scene with Physics
            SpriteView(scene: createPhysicsScene())
                .ignoresSafeArea()

            // Top Bar with Back Button
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .padding()

                    Spacer()

                    // Instructions
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(NSLocalizedString("tomato.garden.title", comment: ""))
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(NSLocalizedString("tomato.garden.shakePhone", comment: ""))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.3))
                            .blur(radius: 10)
                    )
                    .padding(.trailing)
                }

                Spacer()

                // Stats at Bottom
                statsPanel
                    .padding()
            }
        }
        .navigationBarHidden(true)
    }

    private var statsPanel: some View {
        HStack(spacing: 20) {
            StatBubble(
                icon: "🍅",
                value: "\(gardenService.stats.totalTomatoes)",
                label: NSLocalizedString("tomato.garden.total", comment: ""),
                themeManager: themeManager
            )

            StatBubble(
                icon: "⏱️",
                value: gardenService.stats.formattedTotalTime,
                label: NSLocalizedString("tomato.garden.focusTime", comment: ""),
                themeManager: themeManager
            )

            StatBubble(
                icon: "🔥",
                value: "\(gardenService.getTomatoesSortedByDate().count)",
                label: NSLocalizedString("tomato.garden.todayNew", comment: ""),
                themeManager: themeManager
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.3))
                .blur(radius: 10)
        )
    }

    private func createPhysicsScene() -> TomatoPhysicsScene {
        let scene = TomatoPhysicsScene()
        scene.size = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        scene.scaleMode = .aspectFill
        scene.tomatoes = gardenService.getTomatoesSortedByDate()
        return scene
    }
}

// MARK: - Stat Bubble Component
private struct StatBubble: View {
    let icon: String
    let value: String
    let label: String
    let themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 4) {
            Text(icon)
                .font(.system(size: 24))
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

// MARK: - SpriteKit Physics Scene
class TomatoPhysicsScene: SKScene {

    var tomatoes: [Tomato] = []
    private let motionManager = CMMotionManager()

    override func didMove(to view: SKView) {
        super.didMove(to: view)

        // Setup background
        backgroundColor = SKColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 1.0)

        // Setup physics world
        setupPhysicsWorld()

        // Add tomatoes
        addTomatoNodes()

        // Start motion detection
        startMotionDetection()

        // Setup app lifecycle observers for battery optimization
        setupLifecycleObservers()
    }

    private func setupLifecycleObservers() {
        // Stop accelerometer when app enters background (BATTERY OPTIMIZATION)
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.motionManager.stopAccelerometerUpdates()
        }

        // Restart accelerometer when app returns to foreground
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startMotionDetection()
        }
    }

    deinit {
        // Remove observers when scene is deallocated
        NotificationCenter.default.removeObserver(self)
    }

    private func setupPhysicsWorld() {
        // Set initial gravity
        physicsWorld.gravity = CGVector(dx: 0, dy: -9.8)

        // Create boundary around screen
        let boundary = SKPhysicsBody(edgeLoopFrom: frame)
        boundary.friction = 0.3
        boundary.restitution = 0.5
        physicsBody = boundary
    }

    private func addTomatoNodes() {
        // Clear existing nodes
        removeAllChildren()

        // BATTERY OPTIMIZATION: Limit to 25 tomatoes to reduce physics calculations
        let maxTomatoes = min(tomatoes.count, 25)

        if maxTomatoes > 0 {
            // Calculate grid layout
            let columns = 5
            let rows = Int(ceil(Double(maxTomatoes) / Double(columns)))
            let spacing: CGFloat = 10
            let tomatoSize: CGFloat = 60

            let totalWidth = CGFloat(columns) * tomatoSize + CGFloat(columns - 1) * spacing
            let totalHeight = CGFloat(rows) * tomatoSize + CGFloat(rows - 1) * spacing

            let startX = (size.width - totalWidth) / 2 + tomatoSize / 2
            let startY = size.height - (size.height - totalHeight) / 2 - tomatoSize / 2

            for (index, tomato) in tomatoes.prefix(maxTomatoes).enumerated() {
                let col = index % columns
                let row = index / columns

                let x = startX + CGFloat(col) * (tomatoSize + spacing)
                let y = startY - CGFloat(row) * (tomatoSize + spacing)

                // Add small random offset to make it look natural
                let randomOffsetX = CGFloat.random(in: -5...5)
                let randomOffsetY = CGFloat.random(in: -5...5)

                let tomatoNode = createTomatoNode(for: tomato, index: index)
                tomatoNode.position = CGPoint(x: x + randomOffsetX, y: y + randomOffsetY)
                addChild(tomatoNode)
            }
        } else {
            // If no tomatoes, add demo ones
            addDemoTomatoes()
        }
    }

    private func createTomatoNode(for tomato: Tomato, index: Int) -> SKNode {
        let container = SKNode()

        // Create sprite for tomato image
        let imageName = tomato.type.imageName
        let sprite = SKSpriteNode(imageNamed: imageName)

        // Set size based on tomato type
        let baseSize: CGFloat
        switch tomato.type {
        case .classic:  // tmt1
            baseSize = 75  // Larger for classic tomato
        case .curly:    // tmt2
            baseSize = 65
        case .cute:     // tmt3
            baseSize = 65
        case .tmt4:     // tmt4
            baseSize = 68
        case .tmt5:     // tmt5
            baseSize = 68
        case .tmt6:     // tmt6
            baseSize = 68
        case .batman:   // tmt_batman
            baseSize = 70
        case .ironman:  // tmt_ironman
            baseSize = 70
        case .mario:    // tmt_mario
            baseSize = 70
        case .pokemon:  // tmt_pokemon
            baseSize = 70
        case .golden:   // tmt_gold
            baseSize = 72
        case .platinum: // tmt_platinum
            baseSize = 72
        case .diamond:  // tmt_diamond
            baseSize = 78  // Largest for legendary
        }

        let randomScale = CGFloat.random(in: 0.95...1.05)  // Smaller variation
        sprite.size = CGSize(width: baseSize * randomScale, height: baseSize * randomScale)

        container.addChild(sprite)

        // Add physics body - slightly smaller for tighter packing
        let radius = (sprite.size.width + sprite.size.height) / 4.5
        let physicsBody = SKPhysicsBody(circleOfRadius: radius)

        // Physics properties - more stable, heavier for larger tomatoes
        physicsBody.mass = baseSize / 60.0  // Proportional to size
        physicsBody.friction = 0.6  // Increased friction
        physicsBody.restitution = 0.4  // Less bouncy
        physicsBody.linearDamping = 0.2  // More air resistance
        physicsBody.angularDamping = 0.3  // More rotation resistance
        physicsBody.allowsRotation = true

        container.physicsBody = physicsBody
        container.name = "tomato_\(index)"

        return container
    }

    private func addDemoTomatoes() {
        // Add demo tomatoes with grid layout
        let demoCount = 24  // 4 rows x 6 columns
        let columns = 6
        let spacing: CGFloat = 10
        let tomatoSize: CGFloat = 60

        let totalWidth = CGFloat(columns) * tomatoSize + CGFloat(columns - 1) * spacing
        let rows = Int(ceil(Double(demoCount) / Double(columns)))
        let totalHeight = CGFloat(rows) * tomatoSize + CGFloat(rows - 1) * spacing

        let startX = (size.width - totalWidth) / 2 + tomatoSize / 2
        let startY = size.height - (size.height - totalHeight) / 2 - tomatoSize / 2

        for i in 0..<demoCount {
            let col = i % columns
            let row = i / columns

            let x = startX + CGFloat(col) * (tomatoSize + spacing)
            let y = startY - CGFloat(row) * (tomatoSize + spacing)

            // Add small random offset
            let randomOffsetX = CGFloat.random(in: -5...5)
            let randomOffsetY = CGFloat.random(in: -5...5)

            let demoTomato = Tomato(
                type: TomatoType.allCases.randomElement() ?? .classic,
                focusDuration: 1500
            )
            let node = createTomatoNode(for: demoTomato, index: i)
            node.position = CGPoint(x: x + randomOffsetX, y: y + randomOffsetY)
            addChild(node)
        }
    }

    private func startMotionDetection() {
        guard motionManager.isAccelerometerAvailable else {
            print("⚠️ Accelerometer not available")
            return
        }

        // BATTERY OPTIMIZATION: Reduce from 50Hz to 30Hz (still smooth but uses less power)
        motionManager.accelerometerUpdateInterval = 0.033  // 30 Hz (was 0.02 / 50 Hz)

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] (data, error) in
            guard let self = self, let data = data else { return }

            // Map device acceleration to scene gravity
            // Multiply by 9.8 to match Earth's gravity
            let gravityMultiplier: Double = 30.0

            let dx = data.acceleration.x * gravityMultiplier
            let dy = data.acceleration.y * gravityMultiplier

            // Update physics world gravity based on device orientation
            self.physicsWorld.gravity = CGVector(dx: dx, dy: dy)
        }
    }

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        // Stop motion detection when scene is removed
        motionManager.stopAccelerometerUpdates()
    }

    // MARK: - Touch Interaction
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        // Find touched tomato
        let touchedNodes = nodes(at: location)
        for node in touchedNodes {
            if node.name?.starts(with: "tomato_") == true {
                // Apply impulse to make it jump
                let impulse = CGVector(dx: 0, dy: 100)
                node.physicsBody?.applyImpulse(impulse)

                // Add a little spin
                let angularImpulse = CGFloat.random(in: -5...5)
                node.physicsBody?.applyAngularImpulse(angularImpulse)

                // Visual feedback - scale animation
                let scaleUp = SKAction.scale(to: 1.2, duration: 0.1)
                let scaleDown = SKAction.scale(to: 1.0, duration: 0.1)
                let sequence = SKAction.sequence([scaleUp, scaleDown])
                node.run(sequence)
            }
        }
    }
}

// MARK: - Preview
struct PhysicsTomatoGardenView_Previews: PreviewProvider {
    static var previews: some View {
        PhysicsTomatoGardenView()
    }
}

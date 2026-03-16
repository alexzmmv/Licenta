//
//  WebSocketClient.swift
//  GJournal
//
//  WebSocket client for real-time bit updates from server
//

import Foundation
import Combine

class WebSocketClient: ObservableObject {
    @Published var isConnected = false
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTimer: Timer?
    private let baseURL: String
    private let token: String
    private var messageSubject = PassthroughSubject<WebSocketMessage, Never>()
    
    var messagePublisher: AnyPublisher<WebSocketMessage, Never> {
        messageSubject.eraseToAnyPublisher()
    }
    
    init(baseURL: String, token: String) {
        self.baseURL = baseURL
        self.token = token
        print("🔌 [WebSocket] Initialized with base URL: \(baseURL)")
    }
    
    func connect() {
        print("🔌 [WebSocket] Attempting to connect...")
        
        // Convert HTTP URL to WebSocket URL
        guard let urlString = baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")
            .appending("/bits/ws?token=\(token)")
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: urlString) else {
            print("[WebSocket] Invalid URL")
            return
        }
        
        print("🔌 [WebSocket] Connecting to: \(url.absoluteString)")
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        
        isConnected = true
            print("[WebSocket] Connected successfully")
        
        // Start listening for messages
        receiveMessage()
    }
    
    func disconnect() {
        print("🔌 [WebSocket] Disconnecting...")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        print("[WebSocket] Disconnected")
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("📨 [WebSocket] Received message: \(text)")
                    self.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        print("📨 [WebSocket] Received data message: \(text)")
                        self.handleMessage(text)
                    }
                @unknown default:
                    print("[WebSocket] Unknown message type")
                }
                
                // Continue listening
                self.receiveMessage()
                
            case .failure(let error):
                print("[WebSocket] Receive error: \(error.localizedDescription)")
                self.handleDisconnection()
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(WebSocketMessage.self, from: data) else {
            print("[WebSocket] Failed to decode message: \(text)")
            return
        }
        
        print("[WebSocket] Decoded message type: \(message.type)")
        messageSubject.send(message)
    }
    
    private func handleDisconnection() {
        isConnected = false
        print("🔌 [WebSocket] Connection lost. Attempting to reconnect in 5 seconds...")
        
        // Schedule reconnection
        DispatchQueue.main.async {
            self.reconnectTimer?.invalidate()
            self.reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                print("🔌 [WebSocket] Reconnecting...")
                self.connect()
            }
        }
    }
}

// MARK: - Message Types

struct WebSocketMessage: Codable {
    let type: String
    let data: MessageData?
}

struct MessageData: Codable {
    let id: Int?
    let title: String?
    let text: String?
    let emotion: String?
    let intensity: Int?
    let isHidden: Bool?
    let createdAt: String?
    let lastModified: String?
    
    enum CodingKeys: String, CodingKey {
        case id, title, text, emotion, intensity
        case isHidden = "is_hidden"
        case createdAt = "created_at"
        case lastModified = "last_modified"
    }
}

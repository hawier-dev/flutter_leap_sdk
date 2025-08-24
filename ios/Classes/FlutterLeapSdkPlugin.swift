import Flutter
import UIKit
import LeapSDK

public class FlutterLeapSdkPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    
    // Model management
    private var modelRunner: ModelRunner?
    private var isModelLoaded = false
    private var currentModelPath: String?
    private var activeStreamingTask: Task<Void, Never>?
    
    // Conversation management
    private var conversations: [String: Conversation] = [:]
    private var conversationGenerationOptions: [String: [String: Any]] = [:]
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = FlutterLeapSdkPlugin()
        
        // Method channel setup
        let methodChannel = FlutterMethodChannel(name: "flutter_leap_sdk", binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        instance.methodChannel = methodChannel
        
        // Event channel setup for streaming
        let eventChannel = FlutterEventChannel(name: "flutter_leap_sdk_streaming", binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
        instance.eventChannel = eventChannel
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        print("Flutter LEAP SDK iOS: Received method call: \(call.method)")
        
        switch call.method {
        case "loadModel":
            loadModel(call: call, result: result)
        case "generateResponse":
            generateResponse(call: call, result: result)
        case "generateResponseStream":
            startStreamingResponse(call: call, result: result)
        case "cancelStreaming":
            cancelStreaming(result: result)
        case "isModelLoaded":
            result(isModelLoaded)
        case "unloadModel":
            unloadModel(result: result)
        case "createConversation":
            createConversation(call: call, result: result)
        case "generateConversationResponse":
            generateConversationResponse(call: call, result: result)
        case "generateConversationResponseStream":
            generateConversationResponseStream(call: call, result: result)
        case "disposeConversation":
            disposeConversation(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // Helper function to convert ModelLoadingOptions (currently unused by native SDK)
    private func createNativeModelLoadingOptions(from options: [String: Any]?) -> Any? {
        // Note: Native LEAP SDK may not support loading options yet
        // This is prepared for future compatibility
        return nil // For now, use default loading
    }
    
    private func loadModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelPath = args["modelPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Model path is required", details: nil))
            return
        }
        
        let options = args["options"] as? [String: Any]
        
        // Validate input
        guard !modelPath.isEmpty else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Model path cannot be empty", details: nil))
            return
        }
        
        // Secure logging - only log filename
        let fileName = URL(fileURLWithPath: modelPath).lastPathComponent
        print("Flutter LEAP SDK iOS: Loading model: \(fileName)")
        
        // Perform file validation on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let validationResult = self.validateModelFile(at: modelPath)
            
            guard validationResult.isValid else {
                DispatchQueue.main.async {
                    result(FlutterError(code: validationResult.errorCode, 
                                      message: validationResult.errorMessage, 
                                      details: nil))
                }
                return
            }
            
            // Log file info securely
            if let fileSize = validationResult.fileSize {
                print("Flutter LEAP SDK iOS: File size: \(self.formatFileSize(fileSize))")
            }
            
            // Unload existing model first
            self.modelRunner = nil
            self.isModelLoaded = false
            
            // Load model on background task
            Task {
                do {
                    let modelURL = URL(fileURLWithPath: modelPath)
                    
                    self.modelRunner = try await Leap.load(url: modelURL)
                    self.isModelLoaded = true
                    self.currentModelPath = modelPath
                    
                    print("Flutter LEAP SDK iOS: Model loaded successfully")
                    
                    DispatchQueue.main.async {
                        result("Model loaded successfully")
                    }
                } catch {
                    print("Flutter LEAP SDK iOS: Model loading failed: \(type(of: error))")
                    print("Flutter LEAP SDK iOS: Error: \(error.localizedDescription)")
                    
                    DispatchQueue.main.async {
                        let errorMessage = self.formatLeapError(error)
                        result(FlutterError(code: "MODEL_LOADING_ERROR", 
                                          message: errorMessage, 
                                          details: nil))
                    }
                }
            }
        }
    }
    
    private struct FileValidationResult {
        let isValid: Bool
        let errorCode: String
        let errorMessage: String
        let fileSize: Int64?
    }
    
    private func validateModelFile(at path: String) -> FileValidationResult {
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path) else {
            return FileValidationResult(
                isValid: false,
                errorCode: "MODEL_NOT_FOUND",
                errorMessage: "Model file not found",
                fileSize: nil
            )
        }
        
        guard fileManager.isReadableFile(atPath: path) else {
            return FileValidationResult(
                isValid: false,
                errorCode: "MODEL_NOT_READABLE",
                errorMessage: "Cannot read model file (check permissions)",
                fileSize: nil
            )
        }
        
        // Get file size
        do {
            let attributes = try fileManager.attributesOfItem(atPath: path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            guard fileSize > 0 else {
                return FileValidationResult(
                    isValid: false,
                    errorCode: "MODEL_EMPTY",
                    errorMessage: "Model file is empty",
                    fileSize: fileSize
                )
            }
            
            return FileValidationResult(
                isValid: true,
                errorCode: "",
                errorMessage: "",
                fileSize: fileSize
            )
        } catch {
            return FileValidationResult(
                isValid: false,
                errorCode: "MODEL_ACCESS_ERROR",
                errorMessage: "Cannot access model file: \(error.localizedDescription)",
                fileSize: nil
            )
        }
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatLeapError(_ error: Error) -> String {
        let errorDesc = error.localizedDescription
        
        // Provide specific guidance based on error type
        if errorDesc.contains("34") {
            return "Model loading failed (Error 34): Incompatible model format or device architecture. Ensure device supports 64-bit architecture and model is compatible with LEAP SDK."
        } else if errorDesc.contains("load error") {
            return "Model loading error: Check model compatibility with LEAP SDK version 0.4.0+"
        } else if errorDesc.contains("memory") || errorDesc.contains("Memory") {
            return "Model loading failed: Insufficient memory. Try closing other apps or use a smaller model."
        }
        
        return "Model loading failed: \(errorDesc)"
    }
    
    // Helper function to convert Dart GenerationOptions to native GenerationOptions
    private func createNativeGenerationOptions(from options: [String: Any]?) -> GenerationOptions? {
        guard let options = options else { return nil }
        
        var generationOptions = GenerationOptions()
        
        if let temperature = options["temperature"] as? Double {
            generationOptions.temperature = Float(temperature)
        }
        if let topP = options["topP"] as? Double {
            generationOptions.topP = Float(topP)
        }
        if let minP = options["minP"] as? Double {
            generationOptions.minP = Float(minP)
        }
        if let repetitionPenalty = options["repetitionPenalty"] as? Double {
            generationOptions.repetitionPenalty = Float(repetitionPenalty)
        }
        if let maxTokens = options["maxTokens"] as? Int {
            generationOptions.maxTokens = maxTokens
        }
        if let jsonSchema = options["jsonSchema"] as? String {
            generationOptions.jsonSchemaConstraint = jsonSchema
        }
        
        return generationOptions
    }
    
    private func generateResponse(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let runner = modelRunner, isModelLoaded else {
            result(FlutterError(code: "MODEL_NOT_LOADED", message: "Model is not loaded", details: nil))
            return
        }
        
        guard let args = call.arguments as? [String: Any],
              let message = args["message"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Message is required", details: nil))
            return
        }
        
        let systemPrompt = args["systemPrompt"] as? String ?? ""
        let generationOptionsMap = args["generationOptions"] as? [String: Any]
        
        // Validate input
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        guard message.count <= 4096 else {
            result(FlutterError(code: "INPUT_TOO_LONG", message: "Message too long (max 4096 characters)", details: nil))
            return
        }
        
        print("Flutter LEAP SDK iOS: Generating response (\(message.count) chars)")
        
        Task {
            do {
                let conversation = runner.createConversation(systemPrompt: systemPrompt)
                let nativeOptions = createNativeGenerationOptions(from: generationOptionsMap)
                var fullResponse = ""
                
                let chatMessage = ChatMessage(role: .user, content: [.text(message)])
                for try await messageResponse in conversation.generateResponse(message: chatMessage, generationOptions: nativeOptions) {
                    switch messageResponse {
                    case .chunk(let text):
                        fullResponse += text
                    case .reasoningChunk(let text):
                        fullResponse += text
                    case .complete(let finalText, let info):
                        print("Flutter LEAP SDK iOS: Generation completed (\(fullResponse.count) chars)")
                        break
                    @unknown default:
                        // Handle any future cases
                        break
                    }
                }
                
                DispatchQueue.main.async {
                    result(fullResponse)
                }
            } catch {
                print("Flutter LEAP SDK iOS: Error generating response: \(type(of: error))")
                print("Flutter LEAP SDK iOS: Error details: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    result(FlutterError(code: "GENERATION_ERROR", 
                                      message: "Error generating response: \(error.localizedDescription)", 
                                      details: nil))
                }
            }
        }
    }
    
    private func startStreamingResponse(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let runner = modelRunner, isModelLoaded else {
            result(FlutterError(code: "MODEL_NOT_LOADED", message: "Model is not loaded", details: nil))
            return
        }
        
        guard let args = call.arguments as? [String: Any],
              let message = args["message"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Message is required", details: nil))
            return
        }
        
        let systemPrompt = args["systemPrompt"] as? String ?? ""
        let generationOptionsMap = args["generationOptions"] as? [String: Any]
        
        // Validate input
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        guard message.count <= 4096 else {
            result(FlutterError(code: "INPUT_TOO_LONG", message: "Message too long (max 4096 characters)", details: nil))
            return
        }
        
        print("Flutter LEAP SDK iOS: Starting streaming response (\(message.count) chars)")
        
        // Cancel any existing streaming task
        activeStreamingTask?.cancel()
        
        activeStreamingTask = Task {
            do {
                result("Streaming started")
                
                let conversation = runner.createConversation(systemPrompt: systemPrompt)
                let nativeOptions = createNativeGenerationOptions(from: generationOptionsMap)
                
                let chatMessage = ChatMessage(role: .user, content: [.text(message)])
                for try await messageResponse in conversation.generateResponse(message: chatMessage, generationOptions: nativeOptions) {
                    // Check if task was cancelled
                    if Task.isCancelled { break }
                    
                    switch messageResponse {
                    case .chunk(let text):
                        if !text.isEmpty {
                            DispatchQueue.main.async {
                                self.eventSink?(text)
                            }
                        }
                    case .reasoningChunk(let text):
                        if !text.isEmpty {
                            DispatchQueue.main.async {
                                self.eventSink?(text)
                            }
                        }
                    case .complete(let finalText, let info):
                        DispatchQueue.main.async {
                            self.eventSink?("<STREAM_END>")
                        }
                        print("Flutter LEAP SDK iOS: Streaming completed")
                        break
                    @unknown default:
                        // Handle any future cases
                        break
                    }
                }
                
            } catch {
                if error is CancellationError {
                    print("Flutter LEAP SDK iOS: Streaming was cancelled")
                } else {
                    print("Flutter LEAP SDK iOS: Error in streaming: \(type(of: error))")
                    print("Flutter LEAP SDK iOS: Streaming error details: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.eventSink?(FlutterError(code: "STREAMING_ERROR", 
                                                   message: "Error generating streaming response: \(error.localizedDescription)", 
                                                   details: nil))
                    }
                }
            }
        }
    }
    
    private func cancelStreaming(result: @escaping FlutterResult) {
        print("Flutter LEAP SDK iOS: Cancelling streaming")
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        result("Streaming cancelled")
    }
    
    private func unloadModel(result: @escaping FlutterResult) {
        print("Flutter LEAP SDK iOS: Unloading model")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Cancel any active streaming
            self.activeStreamingTask?.cancel()
            self.activeStreamingTask = nil
            
            // Unload model on background thread
            self.modelRunner = nil
            self.isModelLoaded = false
            self.currentModelPath = nil
            
            DispatchQueue.main.async {
                print("Flutter LEAP SDK iOS: Model unloaded successfully")
                result("Model unloaded successfully")
            }
        }
    }
    
    // MARK: - Conversation Management
    
    private func createConversation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let runner = modelRunner, isModelLoaded else {
            result(FlutterError(code: "MODEL_NOT_LOADED", message: "Model is not loaded", details: nil))
            return
        }
        
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId is required", details: nil))
            return
        }
        
        let systemPrompt = args["systemPrompt"] as? String ?? ""
        let generationOptions = args["generationOptions"] as? [String: Any]
        
        print("Flutter LEAP SDK iOS: Creating conversation: \(conversationId)")
        
        // Create conversation
        let conversation = runner.createConversation(systemPrompt: systemPrompt)
        conversations[conversationId] = conversation
        
        // Store generation options if provided
        if let options = generationOptions {
            conversationGenerationOptions[conversationId] = options
        }
        
        result("Conversation created successfully")
    }
    
    private func generateConversationResponse(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String,
              let message = args["message"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId and message are required", details: nil))
            return
        }
        
        guard let conversation = conversations[conversationId] else {
            result(FlutterError(code: "CONVERSATION_NOT_FOUND", message: "Conversation not found: \(conversationId)", details: nil))
            return
        }
        
        // Validate input
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        print("Flutter LEAP SDK iOS: Generating conversation response (\(message.count) chars)")
        
        Task {
            do {
                let storedOptions = conversationGenerationOptions[conversationId]
                let nativeOptions = createNativeGenerationOptions(from: storedOptions)
                var fullResponse = ""
                
                let chatMessage = ChatMessage(role: .user, content: [.text(message)])
                for try await messageResponse in conversation.generateResponse(message: chatMessage, generationOptions: nativeOptions) {
                    switch messageResponse {
                    case .chunk(let text):
                        fullResponse += text
                    case .reasoningChunk(let text):
                        fullResponse += text
                    case .complete(let finalText, let info):
                        print("Flutter LEAP SDK iOS: Conversation generation completed (\(fullResponse.count) chars)")
                        break
                    @unknown default:
                        break
                    }
                }
                
                DispatchQueue.main.async {
                    result(fullResponse)
                }
            } catch {
                print("Flutter LEAP SDK iOS: Error generating conversation response: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    result(FlutterError(code: "GENERATION_ERROR", 
                                      message: "Error generating response: \(error.localizedDescription)", 
                                      details: nil))
                }
            }
        }
    }
    
    private func generateConversationResponseStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String,
              let message = args["message"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId and message are required", details: nil))
            return
        }
        
        guard let conversation = conversations[conversationId] else {
            result(FlutterError(code: "CONVERSATION_NOT_FOUND", message: "Conversation not found: \(conversationId)", details: nil))
            return
        }
        
        // Validate input
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        print("Flutter LEAP SDK iOS: Starting conversation streaming response (\(message.count) chars)")
        result("Streaming started")
        
        // Cancel any existing streaming
        activeStreamingTask?.cancel()
        
        activeStreamingTask = Task {
            do {
                let storedOptions = conversationGenerationOptions[conversationId]
                let nativeOptions = createNativeGenerationOptions(from: storedOptions)
                
                let chatMessage = ChatMessage(role: .user, content: [.text(message)])
                for try await messageResponse in conversation.generateResponse(message: chatMessage, generationOptions: nativeOptions) {
                    // Check for cancellation
                    try Task.checkCancellation()
                    
                    switch messageResponse {
                    case .chunk(let text):
                        if !text.isEmpty {
                            DispatchQueue.main.async {
                                self.eventSink?(text)
                            }
                        }
                    case .reasoningChunk(let text):
                        if !text.isEmpty {
                            DispatchQueue.main.async {
                                self.eventSink?(text)
                            }
                        }
                    case .complete(let finalText, let info):
                        DispatchQueue.main.async {
                            self.eventSink?("<STREAM_END>")
                        }
                        print("Flutter LEAP SDK iOS: Conversation streaming completed")
                        break
                    @unknown default:
                        break
                    }
                }
                
            } catch {
                if error is CancellationError {
                    print("Flutter LEAP SDK iOS: Conversation streaming was cancelled")
                } else {
                    print("Flutter LEAP SDK iOS: Error in conversation streaming: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.eventSink?(FlutterError(code: "STREAMING_ERROR", 
                                                   message: "Error generating streaming response: \(error.localizedDescription)", 
                                                   details: nil))
                    }
                }
            }
        }
    }
    
    private func disposeConversation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId is required", details: nil))
            return
        }
        
        conversations.removeValue(forKey: conversationId)
        conversationGenerationOptions.removeValue(forKey: conversationId)
        
        print("Flutter LEAP SDK iOS: Disposed conversation: \(conversationId)")
        result("Conversation disposed successfully")
    }
}

// MARK: - FlutterStreamHandler
extension FlutterLeapSdkPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        print("Flutter LEAP SDK iOS: Event sink connected")
        self.eventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        print("Flutter LEAP SDK iOS: Event sink disconnected")
        self.eventSink = nil
        return nil
    }
}
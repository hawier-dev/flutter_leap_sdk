import Flutter
import UIKit
import LeapSDK

public class FlutterLeapSdkPlugin: NSObject, FlutterPlugin {
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?
    private var eventSink: FlutterEventSink?
    
    // Model management
    private var modelRunner: ModelRunner?
    
    // Conversation management
    private var conversations: [String: Conversation] = [:]
    private var conversationGenerationOptions: [String: [String: Any]] = [:]
    
    // Function calling support
    private var conversationFunctions: [String: [String: LeapFunction]] = [:]
    
    // Streaming management
    private var activeStreamingTask: Task<Void, Never>?
    private var shouldCancelStreaming = false
    
    // Temporary buffer for streaming data when EventSink is not ready
    private var pendingStreamData: [Any] = []
    private let streamDataLock = NSLock()
    
    
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
        // Send debug info through Flutter channel instead of print
        switch call.method {
        case "loadModel":
            handleLoadModel(call: call, result: result)
        case "generateResponse":
            handleGenerateResponse(call: call, result: result)
        case "generateResponseStream":
            handleGenerateResponseStream(call: call, result: result)
        case "cancelStreaming":
            handleCancelStreaming(call: call, result: result)
        case "isModelLoaded":
            result(modelRunner != nil)
        case "unloadModel":
            handleUnloadModel(call: call, result: result)
        case "createConversation":
            handleCreateConversation(call: call, result: result)
        case "generateConversationResponse":
            handleGenerateConversationResponse(call: call, result: result)
        case "generateConversationResponseStream":
            handleGenerateConversationResponseStream(call: call, result: result)
        case "disposeConversation":
            handleDisposeConversation(call: call, result: result)
        case "generateResponseStructuredStream":
            handleGenerateResponseStructuredStream(call: call, result: result)
        case "registerFunction":
            handleRegisterFunction(call: call, result: result)
        case "unregisterFunction":
            handleUnregisterFunction(call: call, result: result)
        case "executeFunction":
            handleExecuteFunction(call: call, result: result)
        case "generateResponseWithImage":
            handleGenerateResponseWithImage(call: call, result: result)
        case "generateConversationResponseWithImage":
            handleGenerateConversationResponseWithImage(call: call, result: result)
        case "generateResponseWithImageStream":
            handleGenerateResponseWithImageStream(call: call, result: result)
        case "generateConversationResponseWithImageStream":
            handleGenerateConversationResponseWithImageStream(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    // MARK: - Model Management
    
    private func handleLoadModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelPath = args["modelPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "modelPath is required", details: nil))
            return
        }
        
        Task {
            do {
                // Unload existing model if any
                modelRunner = nil
                
                // Load new model
                let modelURL = URL(fileURLWithPath: modelPath)
                let runner = try await Leap.load(url: modelURL)
                
                await MainActor.run {
                    self.modelRunner = runner
                    result("Model loaded successfully")
                }
                
            } catch {
                await MainActor.run {
                    result(FlutterError(code: "MODEL_LOADING_ERROR", 
                                      message: "Error loading model: \(error.localizedDescription)", 
                                      details: nil))
                }
            }
        }
    }
    
    private func handleUnloadModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        modelRunner = nil
        
        // Clear all conversations when model is unloaded
        conversations.removeAll()
        conversationGenerationOptions.removeAll()
        conversationFunctions.removeAll()
        
        result("Model unloaded successfully")
    }
    
    // MARK: - Generation Methods
    
    private func handleGenerateResponse(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let message = args["message"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "message is required", details: nil))
            return
        }
        
        guard let runner = modelRunner else {
            result(FlutterError(code: "MODEL_NOT_LOADED", message: "Model is not loaded", details: nil))
            return
        }
        
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        let systemPrompt = args["systemPrompt"] as? String ?? ""
        
        Task {
            do {
                // Create conversation with optional system prompt
                let conversation = systemPrompt.isEmpty ? 
                    Conversation(modelRunner: runner, history: []) :
                    Conversation(modelRunner: runner, history: [ChatMessage(role: .system, content: [.text(systemPrompt)])])
                
                var fullResponse = ""
                
                // Generate response
                do {
                    let userMessage = ChatMessage(role: .user, content: [.text(message)])
                    for try await response in conversation.generateResponse(message: userMessage) {
                        switch response {
                        case .chunk(let text):
                            fullResponse += text
                        case .reasoningChunk(let text):
                            fullResponse += text
                        case .functionCall(let calls):
                            // Function calls are handled separately in structured streaming
                            break
                        case .complete(let fullText, let completeInfo):
                            break
                        @unknown default:
                        break
                            break
                        }
                    }
                } catch {
                    throw error
                }
                
                await MainActor.run {
                    result(fullResponse)
                }
                
            } catch {
                await MainActor.run {
                    result(FlutterError(code: "GENERATION_ERROR", 
                                      message: "Error generating response: \(error.localizedDescription)", 
                                      details: nil))
                }
            }
        }
    }
    
    private func handleGenerateResponseStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let message = args["message"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "message is required", details: nil))
            return
        }
        
        guard let runner = modelRunner else {
            result(FlutterError(code: "MODEL_NOT_LOADED", message: "Model is not loaded", details: nil))
            return
        }
        
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        let systemPrompt = args["systemPrompt"] as? String ?? ""
        
        // Cancel any active streaming
        activeStreamingTask?.cancel()
        shouldCancelStreaming = false
        
        result("Streaming started")
        
        activeStreamingTask = Task {
            // Ensure cleanup happens like Android's finally block
            defer {
                self.activeStreamingTask = nil
                self.shouldCancelStreaming = false
            }
            
            do {
                // Create conversation with optional system prompt
                let conversation = systemPrompt.isEmpty ? 
                    Conversation(modelRunner: runner, history: []) :
                    Conversation(modelRunner: runner, history: [ChatMessage(role: .system, content: [.text(systemPrompt)])])
                
                // Generate streaming response
                do {
                    let userMessage = ChatMessage(role: .user, content: [.text(message)])
                    for try await response in conversation.generateResponse(message: userMessage) {
                        if shouldCancelStreaming || Task.isCancelled {
                            break
                        }
                        
                        switch response {
                        case .chunk(let text):
                            if !text.isEmpty {
                                await MainActor.run {
                                    self.eventSink?(text)
                                }
                            }
                        case .reasoningChunk(let text):
                            if !text.isEmpty {
                                await MainActor.run {
                                    self.eventSink?(text)
                                }
                            }
                        case .functionCall(let calls):
                            // Function calls are handled separately in structured streaming
                            break
                        case .complete(let fullText, let completeInfo):
                            await MainActor.run {
                                if let sink = self.eventSink {
                                    sink("<STREAM_END>")
                                } else {
                                }
                            }
                            break
                        @unknown default:
                        break
                            break
                        }
                    }
                } catch {
                    throw error
                }
                
            } catch {
                if !(error is CancellationError) {
                    await MainActor.run {
                        self.eventSink?(FlutterError(code: "STREAMING_ERROR", 
                                                   message: "Error generating streaming response: \(error.localizedDescription)", 
                                                   details: nil))
                    }
                }
            }
        }
    }
    
    private func handleCancelStreaming(call: FlutterMethodCall, result: @escaping FlutterResult) {
        shouldCancelStreaming = true
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        
        result("Streaming cancelled")
    }
    
    private func handleGenerateResponseStructuredStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let message = args["message"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "message is required", details: nil))
            return
        }
        
        guard let runner = modelRunner else {
            result(FlutterError(code: "MODEL_NOT_LOADED", message: "Model is not loaded", details: nil))
            return
        }
        
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        let systemPrompt = args["systemPrompt"] as? String ?? ""
        
        // Cancel any active streaming
        activeStreamingTask?.cancel()
        shouldCancelStreaming = false
        
        result("Streaming started")
        
        activeStreamingTask = Task {
            // Ensure cleanup happens like Android's finally block
            defer {
                self.activeStreamingTask = nil
                self.shouldCancelStreaming = false
            }
            
            do {
                // Create conversation with optional system prompt
                let conversation = systemPrompt.isEmpty ? 
                    Conversation(modelRunner: runner, history: []) :
                    Conversation(modelRunner: runner, history: [ChatMessage(role: .system, content: [.text(systemPrompt)])])
                
                // Generate streaming response
                do {
                    let userMessage = ChatMessage(role: .user, content: [.text(message)])
                    for try await response in conversation.generateResponse(message: userMessage) {
                        if shouldCancelStreaming || Task.isCancelled {
                            break
                        }
                        
                        let responseMap = messageResponseToMap(response)
                        await MainActor.run {
                            if let sink = self.eventSink {
                                sink(responseMap)
                            } else {
                                self.streamDataLock.lock()
                                self.pendingStreamData.append(responseMap)
                                self.streamDataLock.unlock()
                            }
                        }
                        
                        // Send stream end for Complete responses
                        if case .complete(_, _) = response {
                            await MainActor.run {
                                if let sink = self.eventSink {
                                    sink("<STREAM_END>")
                                } else {
                                }
                            }
                            break
                        }
                    }
                } catch {
                    throw error
                }
                
            } catch {
                if !(error is CancellationError) {
                    await MainActor.run {
                        self.eventSink?(FlutterError(code: "STREAMING_ERROR", 
                                                   message: "Error generating structured streaming response: \(error.localizedDescription)", 
                                                   details: nil))
                    }
                }
            }
        }
    }
    
    // MARK: - Conversation Management
    
    private func handleCreateConversation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId is required", details: nil))
            return
        }
        
        guard let runner = modelRunner else {
            result(FlutterError(code: "MODEL_NOT_LOADED", message: "Model is not loaded", details: nil))
            return
        }
        
        if conversationId.isEmpty {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId cannot be empty", details: nil))
            return
        }
        
        let systemPrompt = args["systemPrompt"] as? String ?? ""
        let generationOptions = args["generationOptions"] as? [String: Any]
        
        // Create conversation with optional system prompt
        let conversation = systemPrompt.isEmpty ? 
            Conversation(modelRunner: runner, history: []) :
            Conversation(modelRunner: runner, history: [ChatMessage(role: .system, content: [.text(systemPrompt)])])
        
        conversations[conversationId] = conversation
        
        // Store generation options if provided
        if let options = generationOptions {
            conversationGenerationOptions[conversationId] = options
        }
        
        result("Conversation created successfully")
    }
    
    private func handleGenerateConversationResponse(call: FlutterMethodCall, result: @escaping FlutterResult) {
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
        
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        Task {
            do {
                var fullResponse = ""
                
                // Generate response
                do {
                    let userMessage = ChatMessage(role: .user, content: [.text(message)])
                    for try await response in conversation.generateResponse(message: userMessage) {
                        switch response {
                        case .chunk(let text):
                            fullResponse += text
                        case .reasoningChunk(let text):
                            fullResponse += text
                        case .functionCall(let calls):
                            // Function calls are handled separately in structured streaming
                            break
                        case .complete(let fullText, let completeInfo):
                            break
                        @unknown default:
                        break
                            break
                        }
                    }
                } catch {
                    throw error
                }
                
                await MainActor.run {
                    result(fullResponse)
                }
                
            } catch {
                await MainActor.run {
                    result(FlutterError(code: "GENERATION_ERROR", 
                                      message: "Error generating conversation response: \(error.localizedDescription)", 
                                      details: nil))
                }
            }
        }
    }
    
    private func handleGenerateConversationResponseStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String,
              let message = args["message"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId and message are required", details: nil))
            return
        }
        
        // EventSink might not be available yet - will be set by onListen
        // Don't fail here, just log and continue
        if eventSink == nil {
        }
        
        guard let conversation = conversations[conversationId] else {
            result(FlutterError(code: "CONVERSATION_NOT_FOUND", message: "Conversation not found: \(conversationId)", details: nil))
            return
        }
        
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        // Cancel previous streaming and reset state for new message
        if activeStreamingTask != nil {
            shouldCancelStreaming = true
            activeStreamingTask?.cancel()
            activeStreamingTask = nil
        }
        
        // Reset for new streaming
        shouldCancelStreaming = false
        
        result("Streaming started")
        
        activeStreamingTask = Task {
            // Ensure cleanup happens like Android's finally block
            defer {
                self.activeStreamingTask = nil
                self.shouldCancelStreaming = false
            }
            
            do {
                
                // Generate streaming response
                do {
                    var responseCount = 0
                    let userMessage = ChatMessage(role: .user, content: [.text(message)])
                    let responseStream = conversation.generateResponse(message: userMessage)
                    
                    for try await response in responseStream {
                        responseCount += 1
                        
                        if shouldCancelStreaming || Task.isCancelled {
                            break
                        }
                        
                        let responseMap = messageResponseToMap(response)
                        await MainActor.run {
                            if let sink = self.eventSink {
                                sink(responseMap)
                            } else {
                                self.streamDataLock.lock()
                                self.pendingStreamData.append(responseMap)
                                self.streamDataLock.unlock()
                            }
                        }
                        
                        // Send stream end for Complete responses
                        if case .complete(_, _) = response {
                            await MainActor.run {
                                if let sink = self.eventSink {
                                    sink("<STREAM_END>")
                                } else {
                                }
                            }
                            break
                        }
                    }
                    
                    // If we exit the loop without responses, that's the problem!
                    if responseCount == 0 {
                        await MainActor.run {
                            self.eventSink?("<STREAM_END>")
                        }
                    } else {
                    }
                } catch {
                    throw error
                }
                
            } catch {
                if !(error is CancellationError) {
                    await MainActor.run {
                        self.eventSink?(FlutterError(code: "STREAMING_ERROR", 
                                                   message: "Error generating conversation streaming response: \(error.localizedDescription)", 
                                                   details: nil))
                    }
                } else {
                }
            }
        }
    }
    
    private func handleDisposeConversation(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId is required", details: nil))
            return
        }
        
        conversations.removeValue(forKey: conversationId)
        conversationGenerationOptions.removeValue(forKey: conversationId)
        conversationFunctions.removeValue(forKey: conversationId)
        
        result("Conversation disposed successfully")
    }
    
    // MARK: - Function Calling Support
    
    private func handleRegisterFunction(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String,
              let functionName = args["functionName"] as? String,
              let functionSchema = args["functionSchema"] as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId, functionName, and functionSchema are required", details: nil))
            return
        }
        
        guard let conversation = conversations[conversationId] else {
            result(FlutterError(code: "CONVERSATION_NOT_FOUND", message: "Conversation not found: \(conversationId)", details: nil))
            return
        }
        
        do {
            // Initialize conversation functions if not exists
            if conversationFunctions[conversationId] == nil {
                conversationFunctions[conversationId] = [:]
            }
            
            // Create LeapFunction from schema
            let leapFunction = try createLeapFunction(name: functionName, schema: functionSchema)
            
            // Store function for later use
            conversationFunctions[conversationId]![functionName] = leapFunction
            
            // Register function with native LEAP SDK conversation
            conversation.registerFunction(leapFunction)
            
            result("Function registered successfully")
            
        } catch {
            result(FlutterError(code: "FUNCTION_REGISTRATION_ERROR", 
                              message: "Error registering function: \(error.localizedDescription)", 
                              details: nil))
        }
    }
    
    private func handleUnregisterFunction(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String,
              let functionName = args["functionName"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId and functionName are required", details: nil))
            return
        }
        
        guard conversations[conversationId] != nil else {
            result(FlutterError(code: "CONVERSATION_NOT_FOUND", message: "Conversation not found: \(conversationId)", details: nil))
            return
        }
        
        // Remove from stored functions
        conversationFunctions[conversationId]?.removeValue(forKey: functionName)
        
        // Note: LEAP SDK iOS doesn't have explicit unregister method
        // Functions are automatically unregistered when conversation is disposed
        
        result("Function unregistered successfully")
    }
    
    private func handleExecuteFunction(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String,
              let functionCall = args["functionCall"] as? [String: Any],
              let functionName = functionCall["name"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId, functionCall, and functionCall.name are required", details: nil))
            return
        }
        
        guard conversations[conversationId] != nil else {
            result(FlutterError(code: "CONVERSATION_NOT_FOUND", message: "Conversation not found: \(conversationId)", details: nil))
            return
        }
        
        // Check if function is registered
        guard let _ = conversationFunctions[conversationId]?[functionName] else {
            result(FlutterError(code: "FUNCTION_NOT_FOUND", message: "Function '\(functionName)' is not registered", details: nil))
            return
        }
        
        let arguments = functionCall["arguments"] as? [String: Any] ?? [:]
        
        // Bridge function execution back to Flutter
        Task {
            let executionResult = await executeFlutterFunction(name: functionName, arguments: arguments)
            await MainActor.run {
                result(executionResult)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func messageResponseToMap(_ response: MessageResponse) -> [String: Any] {
        switch response {
        case .chunk(let text):
            return [
                "type": "chunk",
                "text": text
            ]
        case .reasoningChunk(let text):
            return [
                "type": "reasoningChunk", 
                "reasoning": text
            ]
        case .functionCall(let calls):
            return [
                "type": "functionCalls",
                "functionCalls": calls.map { call in
                    [
                        "name": call.name,
                        "arguments": call.arguments
                    ]
                }
            ]
        case .complete(let fullText, let info):
            return [
                "type": "complete", 
                "fullText": fullText,
                "finishReason": finishReasonToString(info.finishReason),
                "stats": info.stats != nil ? [
                    "promptTokens": info.stats!.promptTokens,
                    "completionTokens": info.stats!.completionTokens,
                    "totalTokens": info.stats!.totalTokens,
                    "tokensPerSecond": info.stats!.tokenPerSecond
                ] : nil
            ]
        @unknown default:
            return [
                "type": "unknown",
                "data": String(describing: response)
            ]
        }
    }
    
    private func finishReasonToString(_ reason: GenerationFinishReason) -> String {
        switch reason {
        case .stop:
            return "stop"
        case .exceed_context:
            return "length"
        @unknown default:
            return "unknown"
        }
    }
    
    private func createLeapFunction(name: String, schema: [String: Any]) throws -> LeapFunction {
        let description = schema["description"] as? String ?? ""
        let parametersData = schema["parameters"] as? [String: Any] ?? [:]
        let propertiesData = parametersData["properties"] as? [String: Any] ?? [:]
        let requiredList = parametersData["required"] as? [String] ?? []
        
        let parameters = propertiesData.map { (paramName, paramData) in
            let paramMap = paramData as? [String: Any] ?? [:]
            let paramType = paramMap["type"] as? String ?? "string"
            let paramDescription = paramMap["description"] as? String ?? ""
            let isRequired = requiredList.contains(paramName)
            
            return LeapFunctionParameter(
                name: paramName,
                type: convertToLeapFunctionParameterType(paramType, paramMap),
                description: paramDescription,
                optional: !isRequired
            )
        }
        
        return LeapFunction(
            name: name,
            description: description,
            parameters: parameters
        )
    }
    
    private func convertToLeapFunctionParameterType(_ type: String, _ paramData: [String: Any]) -> LeapFunctionParameterType {
        let description = paramData["description"] as? String
        
        switch type {
        case "string":
            let enumValues = paramData["enum"] as? [String]
            return .string(StringType(description: description, enumValues: enumValues))
        case "number":
            let enumValues = paramData["enum"] as? [Double]
            return .number(NumberType(description: description, enumValues: enumValues))
        case "integer":
            let enumValues = paramData["enum"] as? [Int]
            return .integer(IntegerType(description: description, enumValues: enumValues))
        case "boolean":
            return .boolean(BooleanType(description: description))
        case "array":
            let itemsData = paramData["items"] as? [String: Any] ?? [:]
            let itemType = itemsData["type"] as? String ?? "string"
            let itemParameterType = convertToLeapFunctionParameterType(itemType, itemsData)
            return .array(ArrayType(description: description, itemType: itemParameterType))
        case "object":
            let propertiesData = paramData["properties"] as? [String: Any] ?? [:]
            let requiredList = paramData["required"] as? [String] ?? []
            
            let properties = propertiesData.mapValues { propData in
                let propMap = propData as? [String: Any] ?? [:]
                let propType = propMap["type"] as? String ?? "string"
                return convertToLeapFunctionParameterType(propType, propMap)
            }
            
            return .object(ObjectType(description: description, properties: properties, required: requiredList))
        default:
            return .string(StringType(description: description))
        }
    }
    
    private func executeFlutterFunction(name: String, arguments: [String: Any]) async -> [String: Any] {
        // Bridge function execution back to Flutter
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                self.methodChannel?.invokeMethod("executeFunctionCallback", arguments: [
                    "functionName": name,
                    "arguments": arguments
                ]) { result in
                    if let resultMap = result as? [String: Any] {
                        continuation.resume(returning: resultMap)
                    } else {
                        continuation.resume(returning: ["error": "Invalid response from Flutter"])
                    }
                }
            }
        }
    }
    
    // MARK: - Vision Model Support
    
    private func base64ToUIImage(_ base64String: String) -> UIImage? {
        guard let data = Data(base64Encoded: base64String) else {
            return nil
        }
        
        let image = UIImage(data: data)
        if image == nil {
        }
        return image
    }
    
    private func handleGenerateResponseWithImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let message = args["message"] as? String,
              let imageBase64 = args["imageBase64"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "message and imageBase64 are required", details: nil))
            return
        }
        
        guard let runner = modelRunner else {
            result(FlutterError(code: "MODEL_NOT_LOADED", message: "Model is not loaded", details: nil))
            return
        }
        
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        if imageBase64.isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Image data cannot be empty", details: nil))
            return
        }
        
        let systemPrompt = args["systemPrompt"] as? String ?? ""
        
        Task {
            do {
                // Convert base64 to UIImage
                guard let uiImage = base64ToUIImage(imageBase64) else {
                    await MainActor.run {
                        result(FlutterError(code: "IMAGE_ERROR", message: "Failed to decode image", details: nil))
                    }
                    return
                }
                
                // Create conversation with optional system prompt
                let conversation = systemPrompt.isEmpty ? 
                    Conversation(modelRunner: runner, history: []) :
                    Conversation(modelRunner: runner, history: [ChatMessage(role: .system, content: [.text(systemPrompt)])])
                
                // Create image content using UIImage
                let imageContent = try ChatMessageContent.fromUIImage(uiImage, compressionQuality: 0.85)
                let textContent = ChatMessageContent.text(message)
                
                // Create ChatMessage with mixed content
                let chatMessage = ChatMessage(role: .user, content: [textContent, imageContent])
                
                var fullResponse = ""
                
                // Generate response
                for try await response in conversation.generateResponse(message: chatMessage) {
                    switch response {
                    case .chunk(let text):
                        fullResponse += text
                    case .reasoningChunk(let text):
                        fullResponse += text
                    case .functionCall(let calls):
                        break
                    case .complete(let fullText, let completeInfo):
                        break
                    @unknown default:
                        break
                        break
                    }
                }
                
                await MainActor.run {
                    result(fullResponse)
                }
                
            } catch {
                await MainActor.run {
                    result(FlutterError(code: "GENERATION_ERROR", 
                                      message: "Error generating response with image: \(error.localizedDescription)", 
                                      details: nil))
                }
            }
        }
    }
    
    private func handleGenerateConversationResponseWithImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String,
              let message = args["message"] as? String,
              let imageBase64 = args["imageBase64"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId, message, and imageBase64 are required", details: nil))
            return
        }
        
        guard let conversation = conversations[conversationId] else {
            result(FlutterError(code: "CONVERSATION_NOT_FOUND", message: "Conversation not found: \(conversationId)", details: nil))
            return
        }
        
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        if imageBase64.isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Image data cannot be empty", details: nil))
            return
        }
        
        Task {
            do {
                // Convert base64 to UIImage
                guard let uiImage = base64ToUIImage(imageBase64) else {
                    await MainActor.run {
                        result(FlutterError(code: "IMAGE_ERROR", message: "Failed to decode image", details: nil))
                    }
                    return
                }
                
                // Create image content using UIImage
                let imageContent = try ChatMessageContent.fromUIImage(uiImage, compressionQuality: 0.85)
                let textContent = ChatMessageContent.text(message)
                
                // Create ChatMessage with mixed content
                let chatMessage = ChatMessage(role: .user, content: [textContent, imageContent])
                
                var fullResponse = ""
                
                // Generate response
                for try await response in conversation.generateResponse(message: chatMessage) {
                    switch response {
                    case .chunk(let text):
                        fullResponse += text
                    case .reasoningChunk(let text):
                        fullResponse += text
                    case .functionCall(let calls):
                        break
                    case .complete(let fullText, let completeInfo):
                        break
                    @unknown default:
                        break
                        break
                    }
                }
                
                await MainActor.run {
                    result(fullResponse)
                }
                
            } catch {
                await MainActor.run {
                    result(FlutterError(code: "GENERATION_ERROR", 
                                      message: "Error generating conversation response with image: \(error.localizedDescription)", 
                                      details: nil))
                }
            }
        }
    }
    
    private func handleGenerateResponseWithImageStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let message = args["message"] as? String,
              let imageBase64 = args["imageBase64"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "message and imageBase64 are required", details: nil))
            return
        }
        
        guard let runner = modelRunner else {
            result(FlutterError(code: "MODEL_NOT_LOADED", message: "Model is not loaded", details: nil))
            return
        }
        
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        if imageBase64.isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Image data cannot be empty", details: nil))
            return
        }
        
        let systemPrompt = args["systemPrompt"] as? String ?? ""
        
        // Cancel any active streaming
        activeStreamingTask?.cancel()
        shouldCancelStreaming = false
        
        result("Streaming started")
        
        activeStreamingTask = Task {
            // Ensure cleanup happens like Android's finally block
            defer {
                self.activeStreamingTask = nil
                self.shouldCancelStreaming = false
            }
            
            do {
                // Convert base64 to UIImage
                guard let uiImage = base64ToUIImage(imageBase64) else {
                    await MainActor.run {
                        self.eventSink?(FlutterError(code: "IMAGE_ERROR", message: "Failed to decode image", details: nil))
                    }
                    return
                }
                
                // Create conversation with optional system prompt
                let conversation = systemPrompt.isEmpty ? 
                    Conversation(modelRunner: runner, history: []) :
                    Conversation(modelRunner: runner, history: [ChatMessage(role: .system, content: [.text(systemPrompt)])])
                
                // Create image content using UIImage
                let imageContent = try ChatMessageContent.fromUIImage(uiImage, compressionQuality: 0.85)
                let textContent = ChatMessageContent.text(message)
                
                // Create ChatMessage with mixed content
                let chatMessage = ChatMessage(role: .user, content: [textContent, imageContent])
                
                // Generate streaming response
                for try await response in conversation.generateResponse(message: chatMessage) {
                    // Reduced logging - only log important responses
                    if case .complete(_, _) = response {
                    }
                    if shouldCancelStreaming || Task.isCancelled {
                        break
                    }
                    
                    switch response {
                    case .chunk(let text):
                        if !text.isEmpty {
                            await MainActor.run {
                                self.eventSink?(text)
                            }
                        }
                    case .reasoningChunk(let text):
                        if !text.isEmpty {
                            await MainActor.run {
                                self.eventSink?(text)
                            }
                        }
                    case .functionCall(let calls):
                        break
                    case .complete(let fullText, let completeInfo):
                        await MainActor.run {
                            if let sink = self.eventSink {
                                sink("<STREAM_END>")
                            } else {
                            }
                        }
                        break
                    @unknown default:
                        break
                    }
                }
                
            } catch {
                if !(error is CancellationError) {
                    await MainActor.run {
                        self.eventSink?(FlutterError(code: "STREAMING_ERROR", 
                                                   message: "Error generating streaming response with image: \(error.localizedDescription)", 
                                                   details: nil))
                    }
                }
            }
        }
    }
    
    private func handleGenerateConversationResponseWithImageStream(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let conversationId = args["conversationId"] as? String,
              let message = args["message"] as? String,
              let imageBase64 = args["imageBase64"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "conversationId, message, and imageBase64 are required", details: nil))
            return
        }
        
        guard let conversation = conversations[conversationId] else {
            result(FlutterError(code: "CONVERSATION_NOT_FOUND", message: "Conversation not found: \(conversationId)", details: nil))
            return
        }
        
        if message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Message cannot be empty", details: nil))
            return
        }
        
        if imageBase64.isEmpty {
            result(FlutterError(code: "INVALID_INPUT", message: "Image data cannot be empty", details: nil))
            return
        }
        
        // Cancel any active streaming
        activeStreamingTask?.cancel()
        shouldCancelStreaming = false
        
        result("Streaming started")
        
        activeStreamingTask = Task {
            // Ensure cleanup happens like Android's finally block
            defer {
                self.activeStreamingTask = nil
                self.shouldCancelStreaming = false
            }
            
            do {
                // Convert base64 to UIImage
                guard let uiImage = base64ToUIImage(imageBase64) else {
                    await MainActor.run {
                        self.eventSink?(FlutterError(code: "IMAGE_ERROR", message: "Failed to decode image", details: nil))
                    }
                    return
                }
                
                // Create image content using UIImage
                let imageContent = try ChatMessageContent.fromUIImage(uiImage, compressionQuality: 0.85)
                let textContent = ChatMessageContent.text(message)
                
                // Create ChatMessage with mixed content
                let chatMessage = ChatMessage(role: .user, content: [textContent, imageContent])
                
                // Generate streaming response
                for try await response in conversation.generateResponse(message: chatMessage) {
                    if shouldCancelStreaming || Task.isCancelled {
                        break
                    }
                    
                    switch response {
                    case .chunk(let text):
                        if !text.isEmpty {
                            await MainActor.run {
                                self.eventSink?(text)
                            }
                        }
                    case .reasoningChunk(let text):
                        if !text.isEmpty {
                            await MainActor.run {
                                self.eventSink?(text)
                            }
                        }
                    case .functionCall(let calls):
                        break
                    case .complete(let fullText, let completeInfo):
                        await MainActor.run {
                            if let sink = self.eventSink {
                                sink("<STREAM_END>")
                            } else {
                            }
                        }
                        break
                    @unknown default:
                        break
                    }
                }
                
            } catch {
                if !(error is CancellationError) {
                    await MainActor.run {
                        self.eventSink?(FlutterError(code: "STREAMING_ERROR", 
                                                   message: "Error generating conversation streaming response with image: \(error.localizedDescription)", 
                                                   details: nil))
                    }
                }
            }
        }
    }
    
}

// MARK: - FlutterStreamHandler

extension FlutterLeapSdkPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        
        // Reset cancellation flag - new stream starting
        shouldCancelStreaming = false
        
        // Flush any pending buffered data
        streamDataLock.lock()
        if !pendingStreamData.isEmpty {
            for data in pendingStreamData {
                events(data)
            }
            pendingStreamData.removeAll()
        }
        streamDataLock.unlock()
        
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        
        // Clear pending buffer data
        streamDataLock.lock()
        if !pendingStreamData.isEmpty {
            pendingStreamData.removeAll()
        }
        streamDataLock.unlock()
        
        // Cancel any active streaming when EventChannel is cancelled
        shouldCancelStreaming = true
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        return nil
    }
}
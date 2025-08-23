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
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func loadModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let modelPath = args["modelPath"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Model path is required", details: nil))
            return
        }
        
        print("Flutter LEAP SDK iOS: === MODEL LOADING DEBUG ===")
        print("Flutter LEAP SDK iOS: Requested model path: \(modelPath)")
        
        // Check if file exists
        let fileManager = FileManager.default
        let fileExists = fileManager.fileExists(atPath: modelPath)
        print("Flutter LEAP SDK iOS: File exists: \(fileExists)")
        
        guard fileExists else {
            result(FlutterError(code: "MODEL_NOT_FOUND", message: "Model file not found at: \(modelPath)", details: nil))
            return
        }
        
        // Get file info for debugging
        do {
            let fileAttributes = try fileManager.attributesOfItem(atPath: modelPath)
            let fileSize = fileAttributes[.size] as? Int64 ?? 0
            print("Flutter LEAP SDK iOS: File size: \(fileSize) bytes")
            print("Flutter LEAP SDK iOS: File can read: \(fileManager.isReadableFile(atPath: modelPath))")
        } catch {
            print("Flutter LEAP SDK iOS: Could not get file attributes: \(error)")
        }
        
        // List parent directory contents for debugging
        let parentPath = (modelPath as NSString).deletingLastPathComponent
        do {
            let contents = try fileManager.contentsOfDirectory(atPath: parentPath)
            print("Flutter LEAP SDK iOS: Parent directory contents:")
            for item in contents {
                let itemPath = (parentPath as NSString).appendingPathComponent(item)
                let attrs = try? fileManager.attributesOfItem(atPath: itemPath)
                let size = attrs?[.size] as? Int64 ?? 0
                print("Flutter LEAP SDK iOS: - \(item) (\(size) bytes)")
            }
        } catch {
            print("Flutter LEAP SDK iOS: Could not list parent directory: \(error)")
        }
        
        print("Flutter LEAP SDK iOS: Calling Leap.load...")
        
        // Unload existing model first
        modelRunner = nil
        isModelLoaded = false
        
        Task {
            do {
                let modelURL = URL(fileURLWithPath: modelPath)
                print("Flutter LEAP SDK iOS: Loading from URL: \(modelURL)")
                
                modelRunner = try await Leap.load(url: modelURL)
                isModelLoaded = true
                currentModelPath = modelPath
                
                print("Flutter LEAP SDK iOS: Model loaded successfully!")
                
                DispatchQueue.main.async {
                    result("Model loaded successfully from \(modelPath)")
                }
            } catch {
                print("Flutter LEAP SDK iOS: Failed to load model: \(error)")
                print("Flutter LEAP SDK iOS: Error type: \(type(of: error))")
                print("Flutter LEAP SDK iOS: Error description: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    let errorMessage = self.formatLeapError(error)
                    result(FlutterError(code: "MODEL_LOADING_ERROR", 
                                      message: errorMessage, 
                                      details: nil))
                }
            }
        }
    }
    
    private func formatLeapError(_ error: Error) -> String {
        let baseMessage = "Failed to load model: \(error.localizedDescription)"
        
        // Add specific guidance based on error type
        if error.localizedDescription.contains("34") {
            return "\(baseMessage) - This may be due to incompatible model format, device architecture, or corrupted model file."
        } else if error.localizedDescription.contains("load error") {
            return "\(baseMessage) - Check if the model is compatible with LEAP SDK version 0.4.0+"
        }
        
        return baseMessage
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
        
        print("Flutter LEAP SDK iOS: Generating response for: \(message)")
        
        Task {
            do {
                let conversation = runner.createConversation()
                var fullResponse = ""
                
                for try await messageResponse in conversation.generateResponse(message: message) {
                    switch messageResponse {
                    case .chunk(let text):
                        fullResponse += text
                    case .reasoningChunk(let text):
                        fullResponse += text
                    case .complete:
                        print("Flutter LEAP SDK iOS: Generation completed")
                        break
                    }
                }
                
                DispatchQueue.main.async {
                    result(fullResponse)
                }
            } catch {
                print("Flutter LEAP SDK iOS: Error generating response: \(error)")
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
        
        print("Flutter LEAP SDK iOS: Starting streaming response for: \(message)")
        
        // Cancel any existing streaming task
        activeStreamingTask?.cancel()
        
        activeStreamingTask = Task {
            do {
                result("Streaming started")
                
                let conversation = runner.createConversation()
                
                for try await messageResponse in conversation.generateResponse(message: message) {
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
                    case .complete:
                        DispatchQueue.main.async {
                            self.eventSink?("<STREAM_END>")
                        }
                        break
                    }
                }
                
            } catch {
                if error is CancellationError {
                    print("Flutter LEAP SDK iOS: Streaming was cancelled")
                } else {
                    print("Flutter LEAP SDK iOS: Error in streaming response: \(error)")
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
        
        // Cancel any active streaming
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        
        // Unload model
        modelRunner = nil
        isModelLoaded = false
        currentModelPath = nil
        
        result("Model unloaded successfully")
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
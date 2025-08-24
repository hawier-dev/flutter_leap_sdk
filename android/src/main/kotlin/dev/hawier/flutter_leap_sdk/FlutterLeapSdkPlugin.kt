package dev.hawier.flutter_leap_sdk

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import ai.liquid.leap.LeapClient
import ai.liquid.leap.ModelRunner
import ai.liquid.leap.message.MessageResponse
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.onEach
import android.util.Log
import android.os.Handler
import android.os.Looper
import java.io.File
import java.util.concurrent.Executors
import androidx.annotation.WorkerThread
import ai.liquid.leap.LeapFunction

class FlutterLeapSdkPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var eventChannel: EventChannel
  private var modelRunner: ModelRunner? = null
  private val mainScope = MainScope()
  private var streamingSink: EventChannel.EventSink? = null
  private var activeStreamingJob: Job? = null
  private var shouldCancelStreaming = false
  
  // Conversation management
  private val conversations = mutableMapOf<String, ai.liquid.leap.Conversation>()
  private val conversationGenerationOptions = mutableMapOf<String, Map<String, Any>>()
  
  // Function calling support
  private val conversationFunctions = mutableMapOf<String, MutableMap<String, Map<String, Any>>>()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_leap_sdk")
    channel.setMethodCallHandler(this)
    
    eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_leap_sdk_streaming")
    eventChannel.setStreamHandler(
      object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          streamingSink = events
        }

        override fun onCancel(arguments: Any?) {
          streamingSink = null
        }
      }
    )
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "loadModel" -> {
        val modelPath = call.argument<String>("modelPath") ?: ""
        val options = call.argument<Map<String, Any>>("options")
        loadModel(modelPath, options, result)
      }
      "generateResponse" -> {
        val message = call.argument<String>("message") ?: ""
        val systemPrompt = call.argument<String>("systemPrompt") ?: ""
        val generationOptions = call.argument<Map<String, Any>>("generationOptions")
        generateResponse(message, systemPrompt, generationOptions, result)
      }
      "generateResponseStream" -> {
        val message = call.argument<String>("message") ?: ""
        val systemPrompt = call.argument<String>("systemPrompt") ?: ""
        val generationOptions = call.argument<Map<String, Any>>("generationOptions")
        startStreamingResponse(message, systemPrompt, generationOptions, result)
      }
      "cancelStreaming" -> {
        cancelStreaming(result)
      }
      "isModelLoaded" -> {
        result.success(modelRunner != null)
      }
      "unloadModel" -> {
        unloadModel(result)
      }
      "createConversation" -> {
        val conversationId = call.argument<String>("conversationId") ?: ""
        val systemPrompt = call.argument<String>("systemPrompt") ?: ""
        val generationOptions = call.argument<Map<String, Any>>("generationOptions")
        createConversation(conversationId, systemPrompt, generationOptions, result)
      }
      "generateConversationResponse" -> {
        val conversationId = call.argument<String>("conversationId") ?: ""
        val message = call.argument<String>("message") ?: ""
        generateConversationResponse(conversationId, message, result)
      }
      "generateConversationResponseStream" -> {
        val conversationId = call.argument<String>("conversationId") ?: ""
        val message = call.argument<String>("message") ?: ""
        generateConversationResponseStream(conversationId, message, result)
      }
      "disposeConversation" -> {
        val conversationId = call.argument<String>("conversationId") ?: ""
        disposeConversation(conversationId, result)
      }
      "generateResponseStructuredStream" -> {
        val message = call.argument<String>("message") ?: ""
        val systemPrompt = call.argument<String>("systemPrompt") ?: ""
        val generationOptions = call.argument<Map<String, Any>>("generationOptions")
        startStructuredStreamingResponse(message, systemPrompt, generationOptions, result)
      }
      "registerFunction" -> {
        val conversationId = call.argument<String>("conversationId") ?: ""
        val functionName = call.argument<String>("functionName") ?: ""
        val functionSchema = call.argument<Map<String, Any>>("functionSchema") ?: mapOf()
        registerFunction(conversationId, functionName, functionSchema, result)
      }
      "unregisterFunction" -> {
        val conversationId = call.argument<String>("conversationId") ?: ""
        val functionName = call.argument<String>("functionName") ?: ""
        unregisterFunction(conversationId, functionName, result)
      }
      "executeFunction" -> {
        val conversationId = call.argument<String>("conversationId") ?: ""
        val functionCall = call.argument<Map<String, Any>>("functionCall") ?: mapOf()
        executeFunction(conversationId, functionCall, result)
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  // Background thread pool for file I/O operations
  private val fileIOExecutor = Executors.newSingleThreadExecutor()
  
  // Helper function to convert ModelLoadingOptions (currently unused by native SDK)
  private fun createNativeModelLoadingOptions(options: Map<String, Any>?): ai.liquid.leap.ModelLoadingOptions? {
    // Note: Native LEAP SDK may not support all these options yet
    // This is prepared for future compatibility
    return null // For now, use default loading
  }

  private fun loadModel(modelPath: String, options: Map<String, Any>?, result: Result) {
    // Use background thread for file I/O to prevent ANR
    fileIOExecutor.execute {
      mainScope.launch(Dispatchers.IO) {
        try {
          val modelFile = File(modelPath)
          
          // Secure logging - only log essential info in debug builds
          Log.d("FlutterLeapSDK", "Loading model: ${modelFile.name}")
          
          // Validate file existence and readability
          val validationResult = validateModelFile(modelFile)
          if (!validationResult.isValid) {
            withContext(Dispatchers.Main) {
              result.error(validationResult.errorCode, validationResult.errorMessage, null)
            }
            return@launch
          }
          
          // Log file info in debug builds only
          Log.d("FlutterLeapSDK", "File size: ${formatFileSize(modelFile.length())}")
          
          // Unload existing model on background thread
          modelRunner?.unload()
          modelRunner = null
          
          // Load new model
          modelRunner = LeapClient.loadModel(modelPath)
          
          // Switch back to main thread for result
          withContext(Dispatchers.Main) {
            result.success("Model loaded successfully")
          }
          
        } catch (e: Exception) {
          // Error logging
          Log.e("FlutterLeapSDK", "Model loading failed: ${e.javaClass.simpleName}")
          Log.e("FlutterLeapSDK", "Error details: ${e.message}")
          
          val errorMessage = formatLoadingError(e)
          withContext(Dispatchers.Main) {
            result.error("MODEL_LOADING_ERROR", errorMessage, null)
          }
        }
      }
    }
  }
  
  @WorkerThread
  private fun validateModelFile(file: File): FileValidationResult {
    if (!file.exists()) {
      return FileValidationResult(
        isValid = false,
        errorCode = "MODEL_NOT_FOUND",
        errorMessage = "Model file not found"
      )
    }
    
    if (!file.canRead()) {
      return FileValidationResult(
        isValid = false,
        errorCode = "MODEL_NOT_READABLE",
        errorMessage = "Cannot read model file (check permissions)"
      )
    }
    
    if (file.length() == 0L) {
      return FileValidationResult(
        isValid = false,
        errorCode = "MODEL_EMPTY",
        errorMessage = "Model file is empty"
      )
    }
    
    return FileValidationResult(isValid = true)
  }
  
  private fun formatLoadingError(e: Exception): String {
    return when {
      e.message?.contains("34") == true -> 
        "Model loading failed (Error 34): Incompatible model format or device architecture. Ensure device supports ARM64 and model is compatible with LEAP SDK."
      e.message?.contains("load error") == true -> 
        "Model loading error: Check model compatibility with LEAP SDK ${getLeapSDKVersion()}"
      else -> 
        "Model loading failed: ${e.message ?: "Unknown error"}"
    }
  }
  
  private fun formatFileSize(bytes: Long): String {
    return when {
      bytes < 1024 -> "${bytes}B"
      bytes < 1024 * 1024 -> "${bytes / 1024}KB"
      bytes < 1024 * 1024 * 1024 -> "${bytes / 1024 / 1024}MB"
      else -> "${bytes / 1024 / 1024 / 1024}GB"
    }
  }
  
  private data class FileValidationResult(
    val isValid: Boolean,
    val errorCode: String = "",
    val errorMessage: String = ""
  )

  // Helper function to convert Dart GenerationOptions to native GenerationOptions
  private fun createNativeGenerationOptions(options: Map<String, Any>?): ai.liquid.leap.GenerationOptions? {
    if (options == null) return null
    
    return ai.liquid.leap.GenerationOptions().apply {
      options["temperature"]?.let { 
        if (it is Number) temperature = it.toFloat()
      }
      options["topP"]?.let { 
        if (it is Number) topP = it.toFloat() 
      }
      options["minP"]?.let { 
        if (it is Number) minP = it.toFloat() 
      }
      options["repetitionPenalty"]?.let { 
        if (it is Number) repetitionPenalty = it.toFloat() 
      }
      options["maxTokens"]?.let { 
        if (it is Number) maxTokens = it.toInt() 
      }
      options["jsonSchema"]?.let { 
        if (it is String) jsonSchemaConstraint = it
      }
    }
  }

  private fun generateResponse(message: String, systemPrompt: String, generationOptions: Map<String, Any>?, result: Result) {
    val runner = modelRunner
    if (runner == null) {
      result.error("MODEL_NOT_LOADED", "Model is not loaded", null)
      return
    }
    
    // Validate input
    if (message.trim().isEmpty()) {
      result.error("INVALID_INPUT", "Message cannot be empty", null)
      return
    }
    
    if (message.length > 4096) {
      result.error("INPUT_TOO_LONG", "Message too long (max 4096 characters)", null)
      return
    }
    
    mainScope.launch(Dispatchers.IO) {
      try {
        val conversation = runner.createConversation(systemPrompt)
        val nativeOptions = createNativeGenerationOptions(generationOptions)
        var fullResponse = ""
        
        Log.d("FlutterLeapSDK", "Generating response (${message.length} chars)")
        
        conversation.generateResponse(message, nativeOptions)
          .onEach { response ->
            when (response) {
              is MessageResponse.Chunk -> {
                fullResponse += response.text
              }
              is MessageResponse.ReasoningChunk -> {
                val reasoningString = response.toString()
                val textPattern = Regex("ReasoningChunk\\(.*text=([\\s\\S]*)\\)", RegexOption.DOT_MATCHES_ALL)
                val match = textPattern.find(reasoningString)
                val extractedText = match?.groupValues?.get(1) ?: ""
                fullResponse += extractedText
              }
              is MessageResponse.Complete -> {
                Log.d("FlutterLeapSDK", "Generation completed (${fullResponse.length} chars)")
              }
              else -> {
                // Log other response types
                Log.d("FlutterLeapSDK", "Response type: ${response.javaClass.simpleName}")
              }
            }
          }
          .collect { }
        
        withContext(Dispatchers.Main) {
          result.success(fullResponse)
        }
        
      } catch (e: Exception) {
        Log.e("FlutterLeapSDK", "Error generating response: ${e.javaClass.simpleName}")
        Log.e("FlutterLeapSDK", "Error details: ${e.message}")
        
        withContext(Dispatchers.Main) {
          result.error("GENERATION_ERROR", "Error generating response: ${e.message ?: "Unknown error"}", null)
        }
      }
    }
  }

  private fun startStreamingResponse(message: String, systemPrompt: String, generationOptions: Map<String, Any>?, result: Result) {
    val runner = modelRunner
    if (runner == null) {
      result.error("MODEL_NOT_LOADED", "Model is not loaded", null)
      return
    }
    
    // Validate input
    if (message.trim().isEmpty()) {
      result.error("INVALID_INPUT", "Message cannot be empty", null)
      return
    }
    
    if (message.length > 4096) {
      result.error("INPUT_TOO_LONG", "Message too long (max 4096 characters)", null)
      return
    }
    
    activeStreamingJob?.cancel()
    shouldCancelStreaming = false
    
    activeStreamingJob = mainScope.launch(Dispatchers.IO) {
      try {
        withContext(Dispatchers.Main) {
          result.success("Streaming started")
        }
        
        Log.d("FlutterLeapSDK", "Starting stream (${message.length} chars)")
        
        val conversation = runner.createConversation(systemPrompt)
        val nativeOptions = createNativeGenerationOptions(generationOptions)
        
        conversation.generateResponse(message, nativeOptions)
          .onEach { response ->
            if (shouldCancelStreaming) return@onEach
            
            when (response) {
              is MessageResponse.Chunk -> {
                if (response.text.isNotEmpty()) {
                  launch(Dispatchers.Main) {
                    streamingSink?.success(response.text)
                  }
                }
              }
              is MessageResponse.ReasoningChunk -> {
                val reasoningString = response.toString()
                val textPattern = Regex("ReasoningChunk\\(.*text=([\\s\\S]*)\\)", RegexOption.DOT_MATCHES_ALL)
                val match = textPattern.find(reasoningString)
                val extractedText = match?.groupValues?.get(1) ?: ""
                if (extractedText.isNotEmpty()) {
                  launch(Dispatchers.Main) {
                    streamingSink?.success(extractedText)
                  }
                }
              }
              is MessageResponse.Complete -> {
                launch(Dispatchers.Main) {
                  streamingSink?.success("<STREAM_END>")
                }
                Log.d("FlutterLeapSDK", "Streaming completed")
              }
              else -> {
                // Log other response types
                Log.d("FlutterLeapSDK", "Stream response type: ${response.javaClass.simpleName}")
              }
            }
          }
          .collect { }
          
      } catch (e: Exception) {
        if (e is CancellationException) {
          Log.d("FlutterLeapSDK", "Streaming was cancelled")
        } else {
          Log.e("FlutterLeapSDK", "Error in streaming: ${e.javaClass.simpleName}")
          Log.e("FlutterLeapSDK", "Streaming error details: ${e.message}")
          launch(Dispatchers.Main) {
            streamingSink?.error("STREAMING_ERROR", "Error generating streaming response: ${e.message ?: "Unknown error"}", null)
          }
        }
      } finally {
        activeStreamingJob = null
        shouldCancelStreaming = false
      }
    }
  }

  private fun cancelStreaming(result: Result) {
    shouldCancelStreaming = true
    activeStreamingJob?.cancel()
    activeStreamingJob = null
    
    Log.d("FlutterLeapSDK", "Streaming cancelled")
    
    result.success("Streaming cancelled")
  }

  private fun unloadModel(result: Result) {
    mainScope.launch(Dispatchers.IO) {
      try {
        modelRunner?.unload()
        modelRunner = null
        
        Log.d("FlutterLeapSDK", "Model unloaded successfully")
        
        withContext(Dispatchers.Main) {
          result.success("Model unloaded successfully")
        }
      } catch (e: Exception) {
        Log.e("FlutterLeapSDK", "Failed to unload model: ${e.javaClass.simpleName}")
        Log.e("FlutterLeapSDK", "Unload error details: ${e.message}")
        
        withContext(Dispatchers.Main) {
          result.error("UNLOAD_ERROR", "Failed to unload model: ${e.message ?: "Unknown error"}", null)
        }
      }
    }
  }

  private fun getLeapSDKVersion(): String {
    return try {
      // Try to get version from BuildConfig or package info
      "0.4.0" // Current version being used
    } catch (e: Exception) {
      "unknown"
    }
  }
  
  // Helper function to convert MessageResponse to Map for Flutter
  private fun extractFunctionCalls(messageResponse: MessageResponse): List<Map<String, Any>>? {
    // Extract function calls from MessageResponse if available
    // This depends on the native LEAP SDK structure
    return try {
      val functionCalls = messageResponse.functionCalls
      functionCalls?.map { call ->
        mapOf(
          "name" to call.name,
          "arguments" to call.arguments
        )
      }
    } catch (e: Exception) {
      Log.w("FlutterLeapSDK", "Could not extract function calls: ${e.message}")
      null
    }
  }

  private fun messageResponseToMap(response: MessageResponse): Map<String, Any?> {
    return when (response) {
      is MessageResponse.Chunk -> {
        mapOf(
          "type" to "chunk",
          "text" to response.text
        )
      }
      is MessageResponse.ReasoningChunk -> {
        val reasoningString = response.toString()
        val textPattern = Regex("ReasoningChunk\\(.*text=([\\s\\S]*)\\)", RegexOption.DOT_MATCHES_ALL)
        val match = textPattern.find(reasoningString)
        val extractedText = match?.groupValues?.get(1) ?: ""
        mapOf(
          "type" to "reasoningChunk",
          "reasoning" to extractedText
        )
      }
      is MessageResponse.Complete -> {
        mapOf(
          "type" to "complete",
          "fullMessage" to mapOf(
            "role" to "assistant",
            "content" to response.fullMessage?.content ?: "",
            "reasoningContent" to null, // TODO: Extract reasoning from fullMessage
            "functionCalls" to extractFunctionCalls(messageResponse) // Extract function calls from response
          ),
          "finishReason" to when (response.finishReason) {
            // Map native finish reasons to our enum
            else -> "stop"
          },
          "stats" -> response.stats?.let { stats ->
            mapOf(
              "promptTokens" to stats.promptTokens,
              "completionTokens" to stats.completionTokens,
              "timeMs" to stats.timeMs,
              "tokensPerSecond" to stats.tokensPerSecond
            )
          }
        )
      }
      else -> {
        mapOf(
          "type" to "unknown",
          "data" to response.toString()
        )
      }
    }
  }

  private fun startStructuredStreamingResponse(message: String, systemPrompt: String, generationOptions: Map<String, Any>?, result: Result) {
    val runner = modelRunner
    if (runner == null) {
      result.error("MODEL_NOT_LOADED", "Model is not loaded", null)
      return
    }
    
    // Validate input
    if (message.trim().isEmpty()) {
      result.error("INVALID_INPUT", "Message cannot be empty", null)
      return
    }
    
    if (message.length > 4096) {
      result.error("INPUT_TOO_LONG", "Message too long (max 4096 characters)", null)
      return
    }
    
    activeStreamingJob?.cancel()
    shouldCancelStreaming = false
    
    activeStreamingJob = mainScope.launch(Dispatchers.IO) {
      try {
        withContext(Dispatchers.Main) {
          result.success("Streaming started")
        }
        
        Log.d("FlutterLeapSDK", "Starting structured stream (${message.length} chars)")
        
        val conversation = runner.createConversation(systemPrompt)
        val nativeOptions = createNativeGenerationOptions(generationOptions)
        
        conversation.generateResponse(message, nativeOptions)
          .onEach { response ->
            if (shouldCancelStreaming) return@onEach
            
            val responseMap = messageResponseToMap(response)
            
            launch(Dispatchers.Main) {
              streamingSink?.success(responseMap)
            }
            
            // Send stream end for Complete responses
            if (response is MessageResponse.Complete) {
              launch(Dispatchers.Main) {
                streamingSink?.success("<STREAM_END>")
              }
              Log.d("FlutterLeapSDK", "Structured streaming completed")
            }
          }
          .collect { }
          
      } catch (e: Exception) {
        if (e is CancellationException) {
          Log.d("FlutterLeapSDK", "Structured streaming was cancelled")
        } else {
          Log.e("FlutterLeapSDK", "Error in structured streaming: ${e.javaClass.simpleName}")
          Log.e("FlutterLeapSDK", "Structured streaming error details: ${e.message}")
          launch(Dispatchers.Main) {
            streamingSink?.error("STREAMING_ERROR", "Error generating structured streaming response: ${e.message ?: "Unknown error"}", null)
          }
        }
      } finally {
        activeStreamingJob = null
        shouldCancelStreaming = false
      }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    
    // Cancel active streaming
    shouldCancelStreaming = true
    activeStreamingJob?.cancel()
    
    // Cleanup resources
    try {
      CoroutineScope(Dispatchers.IO).launch {
        modelRunner?.unload()
      }
      modelRunner = null
    } catch (e: Exception) {
      // Ignore cleanup errors
      Log.w("FlutterLeapSDK", "Error during cleanup: ${e.message}")
    }
    
    // Shutdown executor
    fileIOExecutor.shutdown()
    
    // Cancel coroutine scope
    mainScope.cancel()
    
    Log.d("FlutterLeapSDK", "Plugin detached and cleaned up")
  }
  
  // MARK: - Conversation Management
  
  private fun createConversation(conversationId: String, systemPrompt: String, generationOptions: Map<String, Any>?, result: Result) {
    val runner = modelRunner
    if (runner == null) {
      result.error("MODEL_NOT_LOADED", "Model is not loaded", null)
      return
    }
    
    if (conversationId.isEmpty()) {
      result.error("INVALID_ARGUMENTS", "conversationId is required", null)
      return
    }
    
    Log.d("FlutterLeapSDK", "Creating conversation: $conversationId")
    
    try {
      // Create conversation
      val conversation = runner.createConversation(systemPrompt)
      conversations[conversationId] = conversation
      
      // Store generation options if provided
      generationOptions?.let {
        conversationGenerationOptions[conversationId] = it
      }
      
      result.success("Conversation created successfully")
    } catch (e: Exception) {
      Log.e("FlutterLeapSDK", "Error creating conversation: ${e.message}")
      result.error("CONVERSATION_ERROR", "Error creating conversation: ${e.message}", null)
    }
  }
  
  private fun generateConversationResponse(conversationId: String, message: String, result: Result) {
    val conversation = conversations[conversationId]
    if (conversation == null) {
      result.error("CONVERSATION_NOT_FOUND", "Conversation not found: $conversationId", null)
      return
    }
    
    if (message.trim().isEmpty()) {
      result.error("INVALID_INPUT", "Message cannot be empty", null)
      return
    }
    
    Log.d("FlutterLeapSDK", "Generating conversation response (${message.length} chars)")
    
    mainScope.launch {
      try {
        withContext(Dispatchers.IO) {
          val storedOptions = conversationGenerationOptions[conversationId]
          val nativeOptions = createNativeGenerationOptions(storedOptions)
          
          val responses = conversation.generateResponse(message, nativeOptions)
          var fullResponse = ""
          
          for (response in responses) {
            fullResponse += response
          }
          
          withContext(Dispatchers.Main) {
            Log.d("FlutterLeapSDK", "Conversation generation completed (${fullResponse.length} chars)")
            result.success(fullResponse)
          }
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          Log.e("FlutterLeapSDK", "Error generating conversation response: ${e.message}")
          result.error("GENERATION_ERROR", "Error generating response: ${e.message}", null)
        }
      }
    }
  }
  
  private fun generateConversationResponseStream(conversationId: String, message: String, result: Result) {
    val conversation = conversations[conversationId]
    if (conversation == null) {
      result.error("CONVERSATION_NOT_FOUND", "Conversation not found: $conversationId", null)
      return
    }
    
    if (message.trim().isEmpty()) {
      result.error("INVALID_INPUT", "Message cannot be empty", null)
      return
    }
    
    Log.d("FlutterLeapSDK", "Starting conversation streaming response (${message.length} chars)")
    result.success("Streaming started")
    
    // Cancel any existing streaming
    activeStreamingJob?.cancel()
    shouldCancelStreaming = false
    
    activeStreamingJob = mainScope.launch {
      try {
        withContext(Dispatchers.IO) {
          val storedOptions = conversationGenerationOptions[conversationId]
          val nativeOptions = createNativeGenerationOptions(storedOptions)
          
          val responses = conversation.generateResponse(message, nativeOptions)
          
          for (response in responses) {
            if (shouldCancelStreaming) {
              Log.d("FlutterLeapSDK", "Conversation streaming cancelled")
              break
            }
            
            if (response.isNotEmpty()) {
              withContext(Dispatchers.Main) {
                streamingSink?.success(response)
              }
            }
          }
          
          withContext(Dispatchers.Main) {
            if (!shouldCancelStreaming) {
              streamingSink?.success("<STREAM_END>")
              Log.d("FlutterLeapSDK", "Conversation streaming completed")
            }
          }
        }
      } catch (e: CancellationException) {
        Log.d("FlutterLeapSDK", "Conversation streaming was cancelled")
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          Log.e("FlutterLeapSDK", "Error in conversation streaming: ${e.message}")
          streamingSink?.error("STREAMING_ERROR", "Error generating streaming response: ${e.message}", null)
        }
      }
    }
  }
  
  private fun disposeConversation(conversationId: String, result: Result) {
    if (conversationId.isEmpty()) {
      result.error("INVALID_ARGUMENTS", "conversationId is required", null)
      return
    }
    
    conversations.remove(conversationId)
    conversationGenerationOptions.remove(conversationId)
    conversationFunctions.remove(conversationId)
    
    Log.d("FlutterLeapSDK", "Disposed conversation: $conversationId")
    result.success("Conversation disposed successfully")
  }

  // MARK: - Function Calling Support
  
  private fun registerFunction(conversationId: String, functionName: String, functionSchema: Map<String, Any>, result: Result) {
    try {
      val conversation = conversations[conversationId]
      if (conversation == null) {
        result.error("CONVERSATION_NOT_FOUND", "Conversation not found: $conversationId", null)
        return
      }

      // Initialize conversation functions map if not exists
      if (!conversationFunctions.containsKey(conversationId)) {
        conversationFunctions[conversationId] = mutableMapOf()
      }

      // Store function schema for later use
      conversationFunctions[conversationId]!![functionName] = functionSchema

      // Register function with native LEAP SDK conversation
      val leapFunction = createLeapFunction(functionName, functionSchema)
      conversation.registerFunction(leapFunction)

      Log.d("FlutterLeapSDK", "Registered function '$functionName' for conversation: $conversationId")
      result.success("Function registered successfully")

    } catch (e: Exception) {
      Log.e("FlutterLeapSDK", "Error registering function: ${e.message}")
      result.error("FUNCTION_REGISTRATION_ERROR", "Error registering function: ${e.message}", null)
    }
  }

  private fun unregisterFunction(conversationId: String, functionName: String, result: Result) {
    try {
      val conversation = conversations[conversationId]
      if (conversation == null) {
        result.error("CONVERSATION_NOT_FOUND", "Conversation not found: $conversationId", null)
        return
      }

      // Remove from stored functions
      conversationFunctions[conversationId]?.remove(functionName)

      // Unregister from native LEAP SDK conversation
      conversation.unregisterFunction(functionName)
      
      Log.d("FlutterLeapSDK", "Unregistered function '$functionName' from conversation: $conversationId")
      result.success("Function unregistered successfully")

    } catch (e: Exception) {
      Log.e("FlutterLeapSDK", "Error unregistering function: ${e.message}")
      result.error("FUNCTION_UNREGISTRATION_ERROR", "Error unregistering function: ${e.message}", null)
    }
  }

  private fun createLeapFunction(name: String, schema: Map<String, Any>): LeapFunction {
    // Convert Flutter function schema to native LEAP SDK LeapFunction
    val description = schema["description"] as? String ?: ""
    val parameters = schema["parameters"] as? Map<String, Any> ?: mapOf()
    
    return LeapFunction(name, description) { args ->
      // This callback will be called by the native LEAP SDK when the function needs to be executed
      // We need to bridge this back to Flutter for actual execution
      executeFlutterFunction(name, args)
    }
  }
  
  private suspend fun executeFlutterFunction(functionName: String, arguments: Map<String, Any>): Map<String, Any> {
    // Bridge function execution back to Flutter
    return try {
      val result = CompletableDeferred<Map<String, Any>>()
      
      Handler(Looper.getMainLooper()).post {
        methodChannel.invokeMethod("executeFunctionCallback", mapOf(
          "functionName" to functionName,
          "arguments" to arguments
        ), object : MethodChannel.Result {
          override fun success(data: Any?) {
            result.complete(data as? Map<String, Any> ?: mapOf("error" to "Invalid response"))
          }
          override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
            result.complete(mapOf("error" to errorMessage))
          }
          override fun notImplemented() {
            result.complete(mapOf("error" to "Function not implemented"))
          }
        })
      }
      
      result.await()
    } catch (e: Exception) {
      mapOf("error" to e.message)
    }
  }

  private fun executeFunction(conversationId: String, functionCall: Map<String, Any>, result: Result) {
    try {
      val functionName = functionCall["name"] as? String
      val arguments = functionCall["arguments"] as? Map<String, Any> ?: mapOf()

      if (functionName == null) {
        result.error("INVALID_FUNCTION_CALL", "Function name is required", null)
        return
      }

      val conversation = conversations[conversationId]
      if (conversation == null) {
        result.error("CONVERSATION_NOT_FOUND", "Conversation not found: $conversationId", null)
        return
      }

      // Check if function is registered
      val functionSchema = conversationFunctions[conversationId]?.get(functionName)
      if (functionSchema == null) {
        result.error("FUNCTION_NOT_FOUND", "Function '$functionName' is not registered", null)
        return
      }

      Log.d("FlutterLeapSDK", "Executing function '$functionName' with ${arguments.size} arguments")

      // Execute function through native LEAP SDK
      // This will trigger the function callback registered with the conversation
      val executionResult = conversation.executeFunction(functionName, arguments)

      result.success(executionResult)

    } catch (e: Exception) {
      Log.e("FlutterLeapSDK", "Error executing function: ${e.message}")
      result.error("FUNCTION_EXECUTION_ERROR", "Error executing function: ${e.message}", null)
    }
  }
}
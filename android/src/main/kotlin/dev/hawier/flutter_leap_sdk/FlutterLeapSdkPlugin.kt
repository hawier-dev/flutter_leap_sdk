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
import java.io.File
import java.util.concurrent.Executors
import androidx.annotation.WorkerThread

class FlutterLeapSdkPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var eventChannel: EventChannel
  private var modelRunner: ModelRunner? = null
  private val mainScope = MainScope()
  private var streamingSink: EventChannel.EventSink? = null
  private var activeStreamingJob: Job? = null
  private var shouldCancelStreaming = false

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
        loadModel(modelPath, result)
      }
      "generateResponse" -> {
        val message = call.argument<String>("message") ?: ""
        generateResponse(message, result)
      }
      "generateResponseStream" -> {
        val message = call.argument<String>("message") ?: ""
        startStreamingResponse(message, result)
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
      else -> {
        result.notImplemented()
      }
    }
  }

  // Background thread pool for file I/O operations
  private val fileIOExecutor = Executors.newSingleThreadExecutor()
  
  private fun loadModel(modelPath: String, result: Result) {
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

  private fun generateResponse(message: String, result: Result) {
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
        val conversation = runner.createConversation()
        var fullResponse = ""
        
        Log.d("FlutterLeapSDK", "Generating response (${message.length} chars)")
        
        conversation.generateResponse(message)
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

  private fun startStreamingResponse(message: String, result: Result) {
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
        
        val conversation = runner.createConversation()
        
        conversation.generateResponse(message)
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

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    
    // Cancel active streaming
    shouldCancelStreaming = true
    activeStreamingJob?.cancel()
    
    // Cleanup resources
    try {
      modelRunner?.unload()
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
}
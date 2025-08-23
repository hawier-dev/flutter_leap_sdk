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

  private fun loadModel(modelPath: String, result: Result) {
    mainScope.launch {
      try {
        val modelFile = File(modelPath)
        Log.d("FlutterLeapSDK", "=== MODEL LOADING DEBUG ===")
        Log.d("FlutterLeapSDK", "Requested model path: $modelPath")
        Log.d("FlutterLeapSDK", "File exists: ${modelFile.exists()}")
        
        if (!modelFile.exists()) {
          result.error("MODEL_NOT_FOUND", "Model file not found at: $modelPath", null)
          return@launch
        }
        
        Log.d("FlutterLeapSDK", "File can read: ${modelFile.canRead()}")
        Log.d("FlutterLeapSDK", "File size: ${modelFile.length()} bytes")
        Log.d("FlutterLeapSDK", "File absolute path: ${modelFile.absolutePath}")
        Log.d("FlutterLeapSDK", "File parent directory: ${modelFile.parentFile?.absolutePath}")
        
        if (!modelFile.canRead()) {
          result.error("MODEL_NOT_READABLE", "Cannot read model file at: $modelPath", null)
          return@launch
        }
        
        // List parent directory contents
        modelFile.parentFile?.let { parentDir ->
          Log.d("FlutterLeapSDK", "Parent directory contents:")
          parentDir.listFiles()?.forEach { file ->
            Log.d("FlutterLeapSDK", "- ${file.name} (${file.length()} bytes, readable: ${file.canRead()})")
          }
        }
        
        Log.d("FlutterLeapSDK", "Calling LeapClient.loadModel...")
        
        // Unload any existing model first
        modelRunner?.unload()
        modelRunner = null
        
        modelRunner = LeapClient.loadModel(modelPath)
        Log.d("FlutterLeapSDK", "Model loaded successfully!")
        result.success("Model loaded successfully from $modelPath")
      } catch (e: Exception) {
        Log.e("FlutterLeapSDK", "Failed to load model", e)
        Log.e("FlutterLeapSDK", "Exception type: ${e.javaClass.simpleName}")
        Log.e("FlutterLeapSDK", "Exception message: ${e.message}")
        Log.e("FlutterLeapSDK", "Exception cause: ${e.cause}")
        
        // Additional debugging for potential file issues
        val modelFile = File(modelPath)
        Log.e("FlutterLeapSDK", "File still exists after error: ${modelFile.exists()}")
        Log.e("FlutterLeapSDK", "File still readable after error: ${modelFile.canRead()}")
        
        // Provide more specific error information
        val errorMessage = when {
            e.message?.contains("34") == true -> "Failed to load model: Executorch Error 34 - This may be due to incompatible model format, device architecture (requires ARM64), or corrupted model file. Details: ${e.message}"
            e.message?.contains("load error") == true -> "Failed to load model: Model loading error - ${e.message}. Check if the model is compatible with LEAP SDK ${getLeapSDKVersion()}"
            else -> "Failed to load model: ${e.message}"
        }
        result.error("MODEL_LOADING_ERROR", errorMessage, null)
      }
    }
  }

  private fun generateResponse(message: String, result: Result) {
    val runner = modelRunner
    if (runner == null) {
      result.error("MODEL_NOT_LOADED", "Model is not loaded", null)
      return
    }
    
    mainScope.launch {
      try {
        val conversation = runner.createConversation()
        var fullResponse = ""
        
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
                Log.d("FlutterLeapSDK", "Generation completed")
              }
              else -> {
                Log.d("FlutterLeapSDK", "Other response type: $response")
              }
            }
          }
          .collect { }
        
        result.success(fullResponse)
      } catch (e: Exception) {
        Log.e("FlutterLeapSDK", "Error generating response", e)
        result.error("GENERATION_ERROR", "Error generating response: ${e.message}", null)
      }
    }
  }

  private fun startStreamingResponse(message: String, result: Result) {
    val runner = modelRunner
    if (runner == null) {
      result.error("MODEL_NOT_LOADED", "Model is not loaded", null)
      return
    }
    
    activeStreamingJob?.cancel()
    shouldCancelStreaming = false
    
    activeStreamingJob = mainScope.launch(Dispatchers.IO) {
      try {
        result.success("Streaming started")
        
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
              }
              else -> {
                Log.d("FlutterLeapSDK", "Other response type: $response")
              }
            }
          }
          .collect { }
          
      } catch (e: Exception) {
        if (e is CancellationException) {
          Log.d("FlutterLeapSDK", "Streaming was cancelled")
        } else {
          Log.e("FlutterLeapSDK", "Error in streaming response", e)
          launch(Dispatchers.Main) {
            streamingSink?.error("STREAMING_ERROR", "Error generating streaming response: ${e.message}", null)
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
    result.success("Streaming cancelled")
  }

  private fun unloadModel(result: Result) {
    mainScope.launch {
      try {
        modelRunner?.unload()
        modelRunner = null
        result.success("Model unloaded successfully")
      } catch (e: Exception) {
        result.error("UNLOAD_ERROR", "Failed to unload model: ${e.message}", null)
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
    activeStreamingJob?.cancel()
    mainScope.cancel()
  }
}
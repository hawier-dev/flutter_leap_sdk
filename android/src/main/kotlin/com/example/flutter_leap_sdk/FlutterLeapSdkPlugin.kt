package com.example.flutter_leap_sdk

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
        if (!modelFile.exists()) {
          result.error("MODEL_NOT_FOUND", "Model file not found at: $modelPath", null)
          return@launch
        }
        
        if (!modelFile.canRead()) {
          result.error("MODEL_NOT_READABLE", "Cannot read model file at: $modelPath", null)
          return@launch
        }
        
        Log.d("FlutterLeapSDK", "Loading model from: $modelPath")
        modelRunner = LeapClient.loadModel(modelPath)
        result.success("Model loaded successfully from $modelPath")
      } catch (e: Exception) {
        Log.e("FlutterLeapSDK", "Failed to load model", e)
        result.error("MODEL_LOADING_ERROR", "Failed to load model: ${e.message}", null)
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
                fullResponse += response.text
              }
              is MessageResponse.Complete -> {
                Log.d("FlutterLeapSDK", "Generation completed")
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
                if (response.text.isNotEmpty()) {
                  launch(Dispatchers.Main) {
                    streamingSink?.success(response.text)
                  }
                }
              }
              is MessageResponse.Complete -> {
                launch(Dispatchers.Main) {
                  streamingSink?.success("<STREAM_END>")
                }
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
    try {
      modelRunner?.unload()
      modelRunner = null
      result.success("Model unloaded successfully")
    } catch (e: Exception) {
      result.error("UNLOAD_ERROR", "Failed to unload model: ${e.message}", null)
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    activeStreamingJob?.cancel()
    mainScope.cancel()
  }
}
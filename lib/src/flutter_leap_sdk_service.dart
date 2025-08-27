import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'exceptions.dart';
import 'leap_logger.dart';
import 'progress_throttler.dart';
import 'conversation.dart';

class FlutterLeapSdkService {
  static const MethodChannel _channel = MethodChannel('flutter_leap_sdk');
  static const EventChannel _streamChannel = EventChannel(
    'flutter_leap_sdk_streaming',
  );

  // State management - replaced static with instance-based
  bool _isModelLoaded = false;
  String _currentLoadedModel = '';
  late Dio _dio;
  final Map<String, CancelToken> _activeDownloads = {};
  
  // Conversation management
  final Map<String, Conversation> _conversations = {};
  
  // Singleton instance
  static FlutterLeapSdkService? _instance;
  static FlutterLeapSdkService get instance {
    _instance ??= FlutterLeapSdkService._internal();
    return _instance!;
  }
  
  FlutterLeapSdkService._internal() {
    LeapLogger.initialize();
    
    _dio = Dio();
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(minutes: 10);
    
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  // Available LEAP models from Liquid AI
  static const Map<String, ModelInfo> availableModels = {
    'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle': ModelInfo(
      fileName: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
      displayName: 'LFM2-350M',
      size: '322 MB',
      url:
          'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-350M-8da4w_output_8da8w-seq_4096.bundle?download=true',
    ),
    'LFM2-700M-8da4w_output_8da8w-seq_4096.bundle': ModelInfo(
      fileName: 'LFM2-700M-8da4w_output_8da8w-seq_4096.bundle',
      displayName: 'LFM2-700M',
      size: '610 MB',
      url:
          'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-700M-8da4w_output_8da8w-seq_4096.bundle?download=true',
    ),
    'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle': ModelInfo(
      fileName: 'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle',
      displayName: 'LFM2-1.2B',
      size: '924 MB',
      url:
          'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle?download=true',
    ),
    'LFM2-VL-1_6B_8da4w.bundle': ModelInfo(
      fileName: 'LFM2-VL-1_6B_8da4w.bundle',
      displayName: 'LFM2-VL-1.6B (Vision)',
      size: '1.6 GB',
      url:
          'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-VL-1_6B_8da4w.bundle?download=true',
    ),
  };

  String get currentLoadedModel => _currentLoadedModel;
  bool get isModelLoaded => _isModelLoaded;
  
  // Static getters for backward compatibility
  static String get currentModel => instance._currentLoadedModel;
  static bool get modelLoaded => instance._isModelLoaded;

  /// Initialize the service (now handled automatically)
  static Future<void> initialize() async {
    // Initialization is now handled in constructor
    await instance._ensureInitialized();
  }
  
  Future<void> _ensureInitialized() async {
    // Dio is initialized in constructor
  }

  /// Load a model from the specified path
  static Future<String> loadModel({String? modelPath, ModelLoadingOptions? options}) async {
    return await instance._loadModel(modelPath: modelPath, options: options);
  }
  
  Future<String> _loadModel({String? modelPath, ModelLoadingOptions? options}) async {
    try {
      String fullPath;
      if (modelPath != null && modelPath.startsWith('/')) {
        fullPath = modelPath;
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        String fileName = modelPath ?? 'model.bundle';
        
        // Check if modelPath is a display name, and if so, convert to actual filename
        if (fileName == 'LFM2-350M') {
          fileName = 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle';
        } else if (fileName == 'LFM2-700M') {
          fileName = 'LFM2-700M-8da4w_output_8da8w-seq_4096.bundle';
        } else if (fileName == 'LFM2-1.2B') {
          fileName = 'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle';
        } else if (fileName == 'LFM2-VL-1.6B (Vision)') {
          fileName = 'LFM2-VL-1_6B_8da4w.bundle';
        }
        // Or find by display name in availableModels
        else {
          final modelInfo = availableModels.values.firstWhere(
            (model) => model.displayName == fileName,
            orElse: () => ModelInfo(fileName: fileName, displayName: fileName, size: '', url: ''),
          );
          fileName = modelInfo.fileName;
        }
        
        fullPath = '${appDir.path}/leap/$fileName';
      }

      final file = File(fullPath);
      final exists = await file.exists();

      if (!exists) {
        throw ModelLoadingException('Model file not found at: $fullPath', 'MODEL_NOT_FOUND');
      }


      final String result = await _channel.invokeMethod('loadModel', {
        'modelPath': fullPath,
        'options': options?.toMap(),
      });
      
      _isModelLoaded = true;
      _currentLoadedModel = fullPath.split('/').last;
      
      return result;
      
    } on PlatformException catch (e) {
      _isModelLoaded = false;
      _currentLoadedModel = '';
      
      throw ModelLoadingException('Failed to load model: ${e.message}', e.code);
    } catch (e) {
      _isModelLoaded = false;
      _currentLoadedModel = '';
      
      rethrow;
    }
  }

  /// Unload the currently loaded model
  static Future<String> unloadModel() async {
    return await instance._unloadModel();
  }
  
  Future<String> _unloadModel() async {
    try {
      final String result = await _channel.invokeMethod('unloadModel');
      
      _isModelLoaded = false;
      _currentLoadedModel = '';
      
      return result;
      
    } on PlatformException catch (e) {
      throw FlutterLeapSdkException(
        'Failed to unload model: ${e.message}',
        e.code,
      );
    }
  }

  /// Check if a model is currently loaded
  static Future<bool> checkModelLoaded() async {
    return await instance._checkModelLoaded();
  }
  
  Future<bool> _checkModelLoaded() async {
    try {
      final bool result = await _channel.invokeMethod('isModelLoaded');
      _isModelLoaded = result;
      
      return result;
      
    } on PlatformException catch (e) {
      throw FlutterLeapSdkException(
        'Failed to check model status: ${e.message}',
        e.code,
      );
    }
  }

  /// Generate a response using the loaded model
  static Future<String> generateResponse(String message, {String? systemPrompt, GenerationOptions? generationOptions}) async {
    return await instance._generateResponse(message, systemPrompt: systemPrompt, generationOptions: generationOptions);
  }
  
  Future<String> _generateResponse(String message, {String? systemPrompt, GenerationOptions? generationOptions}) async {
    if (!_isModelLoaded) {
      throw const ModelNotLoadedException();
    }
    
    // Basic input validation
    if (message.trim().isEmpty) {
      throw GenerationException('Message cannot be empty', 'INVALID_INPUT');
    }
    
    if (message.length > 4096) {
      throw GenerationException('Message too long (max 4096 characters)', 'INPUT_TOO_LONG');
    }

    try {
      final String result = await _channel.invokeMethod('generateResponse', {
        'message': message,
        'systemPrompt': systemPrompt ?? '',
        'generationOptions': generationOptions?.toMap(),
      });
      
      return result;
      
    } on PlatformException catch (e) {
      throw GenerationException(
        'Failed to generate response: ${e.message}',
        e.code,
      );
    }
  }

  /// Generate a streaming response using the loaded model
  static Stream<String> generateResponseStream(String message, {String? systemPrompt, GenerationOptions? generationOptions}) async* {
    yield* instance._generateResponseStream(message, systemPrompt: systemPrompt, generationOptions: generationOptions);
  }
  
  Stream<String> _generateResponseStream(String message, {String? systemPrompt, GenerationOptions? generationOptions}) async* {
    if (!_isModelLoaded) {
      throw const ModelNotLoadedException();
    }
    
    // Basic input validation
    if (message.trim().isEmpty) {
      throw GenerationException('Message cannot be empty', 'INVALID_INPUT');
    }
    
    if (message.length > 4096) {
      throw GenerationException('Message too long (max 4096 characters)', 'INPUT_TOO_LONG');
    }

    try {
      await _channel.invokeMethod('generateResponseStream', {
        'message': message,
        'systemPrompt': systemPrompt ?? '',
        'generationOptions': generationOptions?.toMap(),
      });

      await for (final data in _streamChannel.receiveBroadcastStream()) {
        if (data is String) {
          if (data == '<STREAM_END>') {
            break;
          } else {
            yield data;
          }
        }
      }
      
    } on PlatformException catch (e) {
      throw GenerationException(
        'Failed to generate streaming response: ${e.message}',
        e.code,
      );
    }
  }

  /// Cancel active streaming
  static Future<void> cancelStreaming() async {
    try {
      await _channel.invokeMethod('cancelStreaming');
    } on PlatformException catch (e) {
      throw FlutterLeapSdkException(
        'Failed to cancel streaming: ${e.message}',
        e.code,
      );
    }
  }

  /// Register a function for a conversation
  static Future<String> registerFunction({
    required String conversationId,
    required String functionName,
    required Map<String, dynamic> functionSchema,
  }) async {
    try {
      final String result = await _channel.invokeMethod('registerFunction', {
        'conversationId': conversationId,
        'functionName': functionName,
        'functionSchema': functionSchema,
      });
      
      return result;
    } on PlatformException catch (e) {
      throw FlutterLeapSdkException(
        'Failed to register function: ${e.message}',
        e.code,
      );
    }
  }

  /// Unregister a function from a conversation
  static Future<String> unregisterFunction({
    required String conversationId,
    required String functionName,
  }) async {
    try {
      LeapLogger.info('Unregistering function "$functionName" from conversation: $conversationId');
      
      final String result = await _channel.invokeMethod('unregisterFunction', {
        'conversationId': conversationId,
        'functionName': functionName,
      });
      
      LeapLogger.info('Function "$functionName" unregistered successfully');
      return result;
    } on PlatformException catch (e) {
      LeapLogger.error('Failed to unregister function "$functionName"', e);
      throw FlutterLeapSdkException(
        'Failed to unregister function: ${e.message}',
        e.code,
      );
    }
  }

  /// Execute a function call
  static Future<Map<String, dynamic>> executeFunction({
    required String conversationId,
    required Map<String, dynamic> functionCall,
  }) async {
    try {
      final functionName = functionCall['name'] ?? 'unknown';
      LeapLogger.info('Executing function "$functionName" for conversation: $conversationId');
      
      final Map<Object?, Object?> result = await _channel.invokeMethod('executeFunction', {
        'conversationId': conversationId,
        'functionCall': functionCall,
      });
      
      final Map<String, dynamic> typedResult = result.cast<String, dynamic>();
      
      LeapLogger.info('Function "$functionName" executed successfully');
      return typedResult;
    } on PlatformException catch (e) {
      LeapLogger.error('Failed to execute function', e);
      throw FlutterLeapSdkException(
        'Failed to execute function: ${e.message}',
        e.code,
      );
    }
  }

  /// Download a model with progress monitoring using Dio
  static Future<String> downloadModel({
    String? modelUrl,
    String? modelName,
    Function(DownloadProgress)? onProgress,
  }) async {
    return await instance._downloadModel(
      modelUrl: modelUrl,
      modelName: modelName,
      onProgress: onProgress,
    );
  }

  Future<String> _downloadModel({
    String? modelUrl,
    String? modelName,
    Function(DownloadProgress)? onProgress,
  }) async {
    try {
      String fileName = modelName ?? 'LFM2-350M';
      
      // Map display name to actual filename (same logic as in loadModel)
      if (fileName == 'LFM2-350M') {
        fileName = 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle';
      } else if (fileName == 'LFM2-700M') {
        fileName = 'LFM2-700M-8da4w_output_8da8w-seq_4096.bundle';
      } else if (fileName == 'LFM2-1.2B') {
        fileName = 'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle';
      } else if (fileName == 'LFM2-VL-1.6B (Vision)') {
        fileName = 'LFM2-VL-1_6B_8da4w.bundle';
      }
      // Or find by display name in availableModels
      else {
        final modelInfo = availableModels.values.firstWhere(
          (model) => model.displayName == fileName,
          orElse: () => ModelInfo(fileName: fileName, displayName: fileName, size: '', url: ''),
        );
        fileName = modelInfo.fileName;
      }
      final url = modelUrl ?? availableModels[fileName]?.url ?? 
          'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-350M-8da4w_output_8da8w-seq_4096.bundle?download=true';

      final appDir = await getApplicationDocumentsDirectory();
      final leapDir = Directory('${appDir.path}/leap');

      if (!await leapDir.exists()) {
        await leapDir.create(recursive: true);
      }

      final filePath = '${leapDir.path}/$fileName';
      final tempPath = '$filePath.temp';
      
      // Generate unique download ID
      final downloadId = DateTime.now().millisecondsSinceEpoch.toString();
      final cancelToken = CancelToken();
      _activeDownloads[downloadId] = cancelToken;

      try {
        LeapLogger.info('Starting download: $fileName');
        
        // Create throttler if progress callback is provided
        ProgressThrottler? throttler;
        if (onProgress != null) {
          throttler = ProgressThrottler(
            throttleDuration: const Duration(milliseconds: 200),
            percentageThreshold: 1.0,
            onUpdate: (received, total) {
              final percentage = (received / total * 100);
              final speedEstimate = received > 0 ? '${(received / 1024 / 1024).toStringAsFixed(1)} MB/s' : '0.0 MB/s';
              
              onProgress(DownloadProgress(
                bytesDownloaded: received,
                totalBytes: total,
                percentage: percentage,
                speed: speedEstimate,
              ));
            },
          );
        }
        
        await _dio.download(
          url,
          tempPath,
          cancelToken: cancelToken,
          onReceiveProgress: throttler?.call,
        );

        // Move temp file to final location
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.rename(filePath);
        }
        
        _activeDownloads.remove(downloadId);
        return downloadId;
        
      } catch (e) {
        // Clean up temp file on error
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        _activeDownloads.remove(downloadId);
        rethrow;
      }
    } catch (e) {
      throw DownloadException('Failed to download model: $e', 'DOWNLOAD_ERROR');
    }
  }

  /// Cancel download by downloadId
  static Future<void> cancelDownload(String downloadId) async {
    return await instance._cancelDownload(downloadId);
  }
  
  Future<void> _cancelDownload(String downloadId) async {
    final cancelToken = _activeDownloads[downloadId];
    if (cancelToken != null) {
      cancelToken.cancel('Download cancelled by user');
      _activeDownloads.remove(downloadId);
    }
  }

  /// Check if download is active
  static bool isDownloadActive(String downloadId) {
    return instance._activeDownloads.containsKey(downloadId);
  }
  
  /// Get list of active download IDs
  static List<String> getActiveDownloads() {
    return instance._activeDownloads.keys.toList();
  }

  /// Check if a specific model file exists
  static Future<bool> checkModelExists(String modelName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/leap/$modelName';
      
      final file = File(modelPath);
      final exists = await file.exists();
      
      return exists && (exists ? await file.length() > 0 : false);
      
    } catch (e) {
      throw FlutterLeapSdkException(
        'Failed to check model existence: $e',
        'CHECK_MODEL_ERROR',
      );
    }
  }

  /// Get list of downloaded model filenames
  static Future<List<String>> getDownloadedModels() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final leapDirPath = '${appDir.path}/leap';
      
      final leapDir = Directory(leapDirPath);
      final modelFiles = leapDir.existsSync() ? 
          leapDir.listSync().whereType<File>().map((f) => f.path.split('/').last).toList() : <String>[];
      
      return modelFiles;
      
    } catch (e) {
      throw FlutterLeapSdkException(
        'Failed to get downloaded models: $e',
        'GET_MODELS_ERROR',
      );
    }
  }

  /// Get display name for a model file
  static String getModelDisplayName(String fileName) {
    final modelInfo = availableModels[fileName];
    if (modelInfo != null) {
      return modelInfo.displayName;
    }
    return fileName.replaceAll('.bundle', '');
  }

  /// Get model info for a file
  static ModelInfo? getModelInfo(String fileName) {
    return availableModels[fileName];
  }


  /// Delete a downloaded model file
  static Future<bool> deleteModel(String fileName) async {
    return await instance._deleteModel(fileName);
  }
  
  Future<bool> _deleteModel(String fileName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/leap/$fileName';

      final file = File(modelPath);
      if (await file.exists()) {
        await file.delete();
        
        // Update state if this was the loaded model
        if (_currentLoadedModel == fileName) {
          _currentLoadedModel = '';
          _isModelLoaded = false;
        }
        
        return true;
      }
      
      return false;
      
    } catch (e) {
      throw FlutterLeapSdkException(
        'Failed to delete model: $e',
        'DELETE_MODEL_ERROR',
      );
    }
  }
  
  /// Dispose resources and cleanup
  static void dispose() {
    instance._dispose();
  }
  
  void _dispose() {
    _isModelLoaded = false;
    _currentLoadedModel = '';
    
    // Cancel all active downloads
    for (final cancelToken in _activeDownloads.values) {
      cancelToken.cancel('Service disposed');
    }
    _activeDownloads.clear();
    
    // Dispose all conversations
    _conversations.clear();
  }
  
  /// Get service statistics for debugging
  static Map<String, dynamic> getStats() {
    return {
      'isModelLoaded': instance._isModelLoaded,
      'currentModel': instance._currentLoadedModel,
      'activeDownloads': instance._activeDownloads.length,
      'downloadIds': instance._activeDownloads.keys.toList(),
      'activeConversations': instance._conversations.length,
      'conversationIds': instance._conversations.keys.toList(),
    };
  }

  // MARK: - Conversation Management
  
  /// Create a new conversation with optional system prompt and generation options
  static Future<Conversation> createConversation({
    String? systemPrompt,
    GenerationOptions? generationOptions,
  }) async {
    return await instance._createConversation(
      systemPrompt: systemPrompt,
      generationOptions: generationOptions,
    );
  }
  
  Future<Conversation> _createConversation({
    String? systemPrompt,
    GenerationOptions? generationOptions,
  }) async {
    if (!_isModelLoaded) {
      throw const ModelNotLoadedException();
    }
    
    // Generate unique conversation ID
    final conversationId = DateTime.now().millisecondsSinceEpoch.toString();
    
    try {
      // Create conversation on native side
      await _channel.invokeMethod('createConversation', {
        'conversationId': conversationId,
        'systemPrompt': systemPrompt ?? '',
        'generationOptions': generationOptions?.toMap(),
      });
      
      // Create Dart conversation wrapper
      final conversation = Conversation(
        id: conversationId,
        systemPrompt: systemPrompt,
        generationOptions: generationOptions,
      );
      
      _conversations[conversationId] = conversation;
      
      return conversation;
      
    } catch (e) {
      throw FlutterLeapSdkException('Failed to create conversation: $e', 'CONVERSATION_ERROR');
    }
  }
  
  /// Get an existing conversation by ID
  static Conversation? getConversation(String id) {
    return instance._conversations[id];
  }
  
  /// Get list of all active conversation IDs
  static List<String> getActiveConversationIds() {
    return instance._conversations.keys.toList();
  }
  
  /// Get list of all active conversations
  static List<Conversation> getActiveConversations() {
    return instance._conversations.values.toList();
  }
  
  /// Dispose a conversation and free its resources
  static Future<void> disposeConversation(String conversationId) async {
    await instance._disposeConversation(conversationId);
  }
  
  Future<void> _disposeConversation(String conversationId) async {
    try {
      // Dispose on native side
      await _channel.invokeMethod('disposeConversation', {
        'conversationId': conversationId,
      });
      
      // Remove from local map
      _conversations.remove(conversationId);
      
    } catch (e) {
      throw FlutterLeapSdkException('Failed to dispose conversation: $e', 'CONVERSATION_ERROR');
    }
  }
  
  /// Internal method for conversation response generation
  static Future<String> generateConversationResponse({
    required String conversationId,
    required String message,
    required List<ChatMessage> history,
    GenerationOptions? generationOptions,
  }) async {
    try {
      final String result = await _channel.invokeMethod('generateConversationResponse', {
        'conversationId': conversationId,
        'message': message,
        'history': history.map((m) => m.toMap()).toList(),
        'generationOptions': generationOptions?.toMap(),
      });
      
      return result;
      
    } on PlatformException catch (e) {
      throw GenerationException('Failed to generate response: ${e.message}', e.code);
    }
  }
  
  /// Internal method for conversation streaming response generation
  static Stream<String> generateConversationResponseStream({
    required String conversationId,
    required String message,
    required List<ChatMessage> history,
    GenerationOptions? generationOptions,
  }) async* {
    try {
      await _channel.invokeMethod('generateConversationResponseStream', {
        'conversationId': conversationId,
        'message': message,
        'history': history.map((m) => m.toMap()).toList(),
        'generationOptions': generationOptions?.toMap(),
      });

      await for (final data in _streamChannel.receiveBroadcastStream()) {
        if (data is String) {
          if (data == '<STREAM_END>') {
            break;
          } else {
            yield data;
          }
        } else if (data is Map) {
          // Handle structured responses from native - cast to Map<String, dynamic>
          final dataMap = Map<String, dynamic>.from(data);
          final type = dataMap['type'] as String?;
          switch (type) {
            case 'chunk':
              yield dataMap['text'] as String? ?? '';
              break;
            case 'reasoningChunk':
              // For now, skip reasoning chunks in simple streaming
              break;
            case 'functionCalls':
              // For now, skip function calls in simple streaming
              break;
            case 'complete':
              // Stream end
              break;
            default:
              // Unknown type, treat as chunk
              yield data.toString();
          }
        }
      }
      
    } on PlatformException catch (e) {
      throw GenerationException('Failed to generate streaming response: ${e.message}', e.code);
    }
  }

  /// Generate structured streaming response for conversations with MessageResponse objects
  static Stream<MessageResponse> generateConversationResponseStructured({
    required String conversationId,
    required String message,
    required List<ChatMessage> history,
    GenerationOptions? generationOptions,
  }) async* {
    try {
      await _channel.invokeMethod('generateConversationResponseStream', {
        'conversationId': conversationId,
        'message': message,
        'history': history.map((m) => m.toMap()).toList(),
        'generationOptions': generationOptions?.toMap(),
      });

      await for (final data in _streamChannel.receiveBroadcastStream()) {
        // Handle error data specially
        if (data is Map && data.containsKey('error')) {
          final errorMap = Map<String, dynamic>.from(data);
          final errorCode = errorMap['code'] as String? ?? 'UNKNOWN_ERROR';
          final errorMessage = errorMap['message'] as String? ?? 'Unknown error occurred';
          
          if (errorCode == 'GENERATION_TIMEOUT' || errorMessage.contains('stopped unexpectedly')) {
            throw GenerationException('Generation stopped unexpectedly', errorCode);
          } else {
            throw GenerationException(errorMessage, errorCode);
          }
        }
        
        if (data is String) {
          if (data == '<STREAM_END>') {
            yield MessageResponseComplete(
              message: ChatMessage.assistant(''), // Will be updated by conversation
              finishReason: GenerationFinishReason.stop,
              stats: null,
            );
            break;
          } else {
            // Plain text chunk
            yield MessageResponseChunk(data);
          }
        } else if (data is Map) {
          // Handle structured responses from native - cast to Map<String, dynamic>
          final dataMap = Map<String, dynamic>.from(data);
          final type = dataMap['type'] as String?;
          switch (type) {
            case 'chunk':
              final text = dataMap['text'] as String? ?? '';
              yield MessageResponseChunk(text);
              break;
            case 'reasoningChunk':
              final reasoning = dataMap['reasoning'] as String? ?? '';
              yield MessageResponseReasoningChunk(reasoning);
              break;
            case 'functionCalls':
              final functionCallsData = dataMap['functionCalls'] as List<dynamic>? ?? [];
              final functionCalls = functionCallsData.map((callData) => 
                LeapFunctionCall.fromMap(Map<String, dynamic>.from(callData as Map))
              ).toList();
              yield MessageResponseFunctionCalls(functionCalls);
              break;
            case 'complete':
              final finishReasonStr = dataMap['finishReason'] as String? ?? 'stop';
              final finishReason = GenerationFinishReason.values.firstWhere(
                (e) => e.name == finishReasonStr,
                orElse: () => GenerationFinishReason.stop,
              );
              
              yield MessageResponseComplete(
                message: ChatMessage.assistant(''), // Will be updated by conversation
                finishReason: finishReason,
                stats: null, // TODO: Parse stats from native
              );
              break;
            default:
              // Unknown type, treat as chunk
              yield MessageResponseChunk(data.toString());
          }
        }
      }
      
    } on PlatformException catch (e) {
      // Handle specific timeout and generation errors
      if (e.code == 'GENERATION_TIMEOUT' || e.code == 'GENERATION_ERROR' || 
          (e.message != null && e.message!.contains('stopped unexpectedly'))) {
        throw GenerationException('Generation stopped unexpectedly', e.code);
      }
      
      throw GenerationException('Failed to generate structured streaming response: ${e.message}', e.code);
    }
  }

  /// Handle method calls from native platforms (e.g., function execution callbacks)
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'executeFunctionCallback':
          return await _handleFunctionExecution(call.arguments);
        default:
          throw PlatformException(
            code: 'UNIMPLEMENTED',
            message: 'Method ${call.method} not implemented',
          );
      }
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Handle function execution callback from native platforms
  Future<Map<String, dynamic>> _handleFunctionExecution(dynamic arguments) async {
    try {
      final args = arguments as Map<String, dynamic>;
      final functionName = args['functionName'] as String;
      final functionArgs = args['arguments'] as Map<String, dynamic>;


      // Find the conversation and execute the function
      // This requires looking through all conversations to find the one with this function
      for (final conversation in _conversations.values) {
        if (conversation.hasFunction(functionName)) {
          final functionCall = LeapFunctionCall(
            name: functionName,
            arguments: functionArgs,
          );
          final result = await conversation.executeFunction(functionCall);
          return result;
        }
      }

      // Function not found in any conversation
      throw GenerationException(
        'Function "$functionName" not found in any active conversation',
        'FUNCTION_NOT_FOUND',
      );

    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // MARK: - Vision Model Support

  /// Generate a response with an image using the loaded vision model
  static Future<String> generateResponseWithImage(
    String message, 
    Uint8List imageBytes, {
    String? systemPrompt, 
    GenerationOptions? generationOptions
  }) async {
    return await instance._generateResponseWithImage(
      message, 
      imageBytes, 
      systemPrompt: systemPrompt, 
      generationOptions: generationOptions
    );
  }
  
  Future<String> _generateResponseWithImage(
    String message, 
    Uint8List imageBytes, {
    String? systemPrompt, 
    GenerationOptions? generationOptions
  }) async {
    if (!_isModelLoaded) {
      throw const ModelNotLoadedException();
    }
    
    if (message.trim().isEmpty) {
      throw GenerationException('Message cannot be empty', 'INVALID_INPUT');
    }
    
    if (imageBytes.isEmpty) {
      throw GenerationException('Image data cannot be empty', 'INVALID_INPUT');
    }

    try {
      final String imageBase64 = base64Encode(imageBytes);
      
      final String result = await _channel.invokeMethod('generateResponseWithImage', {
        'message': message,
        'systemPrompt': systemPrompt ?? '',
        'imageBase64': imageBase64,
        'generationOptions': generationOptions?.toMap(),
      });
      
      return result;
      
    } on PlatformException catch (e) {
      throw GenerationException(
        'Failed to generate response with image: ${e.message}',
        e.code,
      );
    }
  }

}

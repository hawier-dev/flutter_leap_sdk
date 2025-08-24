import 'dart:async';
import 'dart:io';
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
    // Initialize logging
    LeapLogger.initialize();
    
    // Initialize Dio
    _dio = Dio();
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(minutes: 10);
    
    LeapLogger.info('FlutterLeapSdkService initialized');
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
    LeapLogger.info('Service initialization complete');
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
        final fileName = modelPath ?? 'model.bundle';
        fullPath = '${appDir.path}/leap/$fileName';
      }

      LeapLogger.modelOp('Loading model', details: 'path: $fullPath');

      // Use cached file operations instead of direct I/O
      final file = File(fullPath);
      final exists = await file.exists();
      
      LeapLogger.fileOp('check_exists', fullPath, details: 'exists: $exists');

      if (!exists) {
        LeapLogger.warning('Model file does not exist or is empty: $fullPath');
        
        // List available files for debugging
        final appDir = await getApplicationDocumentsDirectory();
        final leapDir = Directory('${appDir.path}/leap');
        final availableFiles = leapDir.existsSync() ? 
            leapDir.listSync().whereType<File>().map((f) => f.path.split('/').last).toList() : <String>[];
        
        if (availableFiles.isNotEmpty) {
          LeapLogger.info('Available models: ${availableFiles.join(', ')}');
        } else {
          LeapLogger.warning('No model files found in leap directory');
        }
        
        throw ModelLoadingException('Model file not found at: $fullPath', 'MODEL_NOT_FOUND');
      }

      final size = await file.length();
      LeapLogger.fileOp('file_info', fullPath, details: '${(size / 1024 / 1024).toStringAsFixed(1)} MB');

      final String result = await _channel.invokeMethod('loadModel', {
        'modelPath': fullPath,
        'options': options?.toMap(),
      });
      
      _isModelLoaded = true;
      _currentLoadedModel = fullPath.split('/').last;
      
      LeapLogger.modelOp('Model loaded successfully', modelName: _currentLoadedModel);
      return result;
      
    } on PlatformException catch (e) {
      _isModelLoaded = false;
      _currentLoadedModel = '';
      
      LeapLogger.error('Model loading failed', e);
      throw ModelLoadingException('Failed to load model: ${e.message}', e.code);
    } catch (e) {
      _isModelLoaded = false;
      _currentLoadedModel = '';
      
      LeapLogger.error('Unexpected error during model loading', e);
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
      
      final previousModel = _currentLoadedModel;
      _isModelLoaded = false;
      _currentLoadedModel = '';
      
      LeapLogger.modelOp('Model unloaded successfully', modelName: previousModel);
      return result;
      
    } on PlatformException catch (e) {
      LeapLogger.error('Failed to unload model', e);
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
      
      LeapLogger.debug('Model loaded status: $result');
      return result;
      
    } on PlatformException catch (e) {
      LeapLogger.error('Failed to check model status', e);
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
      LeapLogger.info('Generating response (${message.length} chars)');
      
      final String result = await _channel.invokeMethod('generateResponse', {
        'message': message,
        'systemPrompt': systemPrompt ?? '',
        'generationOptions': generationOptions?.toMap(),
      });
      
      LeapLogger.info('Response generated (${result.length} chars)');
      return result;
      
    } on PlatformException catch (e) {
      LeapLogger.error('Failed to generate response', e);
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
      LeapLogger.info('Starting streaming response (${message.length} chars)');
      
      await _channel.invokeMethod('generateResponseStream', {
        'message': message,
        'systemPrompt': systemPrompt ?? '',
        'generationOptions': generationOptions?.toMap(),
      });

      await for (final data in _streamChannel.receiveBroadcastStream()) {
        if (data is String) {
          if (data == '<STREAM_END>') {
            LeapLogger.info('Streaming response completed');
            break;
          } else {
            yield data;
          }
        }
      }
      
    } on PlatformException catch (e) {
      LeapLogger.error('Failed to generate streaming response', e);
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
      LeapLogger.info('Streaming cancelled');
    } on PlatformException catch (e) {
      LeapLogger.error('Failed to cancel streaming', e);
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
      LeapLogger.info('Registering function "$functionName" for conversation: $conversationId');
      
      final String result = await _channel.invokeMethod('registerFunction', {
        'conversationId': conversationId,
        'functionName': functionName,
        'functionSchema': functionSchema,
      });
      
      LeapLogger.info('Function "$functionName" registered successfully');
      return result;
    } on PlatformException catch (e) {
      LeapLogger.error('Failed to register function "$functionName"', e);
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
      final fileName = modelName ?? 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle';
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
          LeapLogger.info('Download completed: $fileName');
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
      LeapLogger.error('Download failed', e);
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
      LeapLogger.info('Download cancelled: $downloadId');
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
      
      // Use cached file operations
      final file = File(modelPath);
      final exists = await file.exists();
      
      LeapLogger.fileOp('check_model_exists', modelPath, 
        details: 'exists: $exists, size: ${exists ? '${(await file.length() / 1024 / 1024).toStringAsFixed(1)} MB' : '0 MB'}');

      return exists && (exists ? await file.length() > 0 : false);
      
    } catch (e) {
      LeapLogger.error('Error checking model existence: $modelName', e);
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
      
      // Use background file operations
      final leapDir = Directory(leapDirPath);
      final modelFiles = leapDir.existsSync() ? 
          leapDir.listSync().whereType<File>().map((f) => f.path.split('/').last).toList() : <String>[];
      
      LeapLogger.info('Found ${modelFiles.length} downloaded models: ${modelFiles.join(', ')}');
      return modelFiles;
      
    } catch (e) {
      LeapLogger.error('Failed to get downloaded models', e);
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
          LeapLogger.modelOp('Unloaded deleted model', modelName: fileName);
        }
        
        LeapLogger.fileOp('delete_model', modelPath, details: 'success');
        return true;
      }
      
      LeapLogger.warning('Model file does not exist: $fileName');
      return false;
      
    } catch (e) {
      LeapLogger.error('Failed to delete model: $fileName', e);
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
    
    LeapLogger.info('FlutterLeapSdkService disposed');
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
      
      LeapLogger.info('Created conversation: $conversationId');
      return conversation;
      
    } catch (e) {
      LeapLogger.error('Failed to create conversation', e);
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
      
      LeapLogger.info('Disposed conversation: $conversationId');
      
    } catch (e) {
      LeapLogger.error('Failed to dispose conversation: $conversationId', e);
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
      LeapLogger.error('Failed to generate conversation response', e);
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
        }
      }
      
    } on PlatformException catch (e) {
      LeapLogger.error('Failed to generate conversation streaming response', e);
      throw GenerationException('Failed to generate streaming response: ${e.message}', e.code);
    }
  }
}

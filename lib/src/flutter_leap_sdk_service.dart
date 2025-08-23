import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'exceptions.dart';
import 'download_manager.dart';
import 'background_file_ops.dart';
import 'file_cache.dart';
import 'leap_logger.dart';

class FlutterLeapSdkService {
  static const MethodChannel _channel = MethodChannel('flutter_leap_sdk');
  static const EventChannel _streamChannel = EventChannel(
    'flutter_leap_sdk_streaming',
  );

  // State management - replaced static with instance-based
  bool _isModelLoaded = false;
  String _currentLoadedModel = '';
  
  // Singleton instance
  static FlutterLeapSdkService? _instance;
  static FlutterLeapSdkService get instance {
    _instance ??= FlutterLeapSdkService._internal();
    return _instance!;
  }
  
  FlutterLeapSdkService._internal() {
    // Initialize logging
    LeapLogger.initialize();
    
    // Initialize download manager
    DownloadManager.initialize();
    
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
  static String get currentLoadedModel => instance._currentLoadedModel;
  static bool get isModelLoaded => instance._isModelLoaded;

  /// Initialize the service (now handled automatically)
  static Future<void> initialize() async {
    // Initialization is now handled in constructor
    await instance._ensureInitialized();
  }
  
  Future<void> _ensureInitialized() async {
    // Download manager initialization is handled automatically
    LeapLogger.info('Service initialization complete');
  }

  /// Load a model from the specified path
  static Future<String> loadModel({String? modelPath}) async {
    return await instance._loadModel(modelPath: modelPath);
  }
  
  Future<String> _loadModel({String? modelPath}) async {
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
      final fileInfo = await FileCache.getFileInfo(fullPath);
      
      LeapLogger.fileOp('check_exists', fullPath, details: 'exists: ${fileInfo.exists}');

      if (fileInfo.exists && fileInfo.size > 0) {
        LeapLogger.fileOp('file_info', fullPath, details: fileInfo.sizeFormatted);
      } else {
        LeapLogger.warning('Model file does not exist or is empty: $fullPath');
        
        // List available files for debugging
        final appDir = await getApplicationDocumentsDirectory();
        final availableFiles = await BackgroundFileOps.listModelFiles('${appDir.path}/leap');
        
        if (availableFiles.isNotEmpty) {
          LeapLogger.info('Available models: ${availableFiles.join(', ')}');
        } else {
          LeapLogger.warning('No model files found in leap directory');
        }
        
        throw ModelLoadingException('Model file not found at: $fullPath', 'MODEL_NOT_FOUND');
      }

      final String result = await _channel.invokeMethod('loadModel', {
        'modelPath': fullPath,
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
  static Future<String> generateResponse(String message) async {
    return await instance._generateResponse(message);
  }
  
  Future<String> _generateResponse(String message) async {
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
  static Stream<String> generateResponseStream(String message) async* {
    yield* instance._generateResponseStream(message);
  }
  
  Stream<String> _generateResponseStream(String message) async* {
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

  /// Download a model using optimized download manager
  static Future<String?> downloadModel({
    String? modelUrl,
    String? modelName,
    Function(DownloadProgress)? onProgress,
  }) async {
    return await DownloadManager.downloadModel(
      modelUrl: modelUrl,
      modelName: modelName,
      onProgress: onProgress,
    );
  }

  // Removed inefficient polling-based progress monitoring
  // Now handled by event-driven DownloadManager

  /// Cancel download by taskId
  static Future<void> cancelDownload(String taskId) async {
    return await DownloadManager.cancelDownload(taskId);
  }

  /// Pause download by taskId
  static Future<void> pauseDownload(String taskId) async {
    return await DownloadManager.pauseDownload(taskId);
  }

  /// Resume download by taskId
  static Future<String?> resumeDownload(String taskId) async {
    return await DownloadManager.resumeDownload(taskId);
  }

  /// Retry failed download by taskId
  static Future<String?> retryDownload(String taskId) async {
    await _ensureDownloaderInitialized();

    try {
      return await FlutterDownloader.retry(taskId: taskId);
    } catch (e) {
      throw DownloadException('Failed to retry download: $e', 'RETRY_ERROR');
    }
  }

  /// Get download status for a taskId (deprecated - use DownloadManager directly)
  @deprecated
  static Future<DownloadTaskStatus?> getDownloadStatus(String taskId) async {
    // This method is deprecated - use DownloadManager.getDownloadProgress instead
    final progress = await DownloadManager.getDownloadProgress(taskId);
    return progress != null ? DownloadTaskStatus.running : null;
  }

  /// Get download progress for a taskId
  static Future<DownloadProgress?> getDownloadProgress(String taskId) async {
    return await DownloadManager.getDownloadProgress(taskId);
  }

  /// Move completed download from temp file to final location
  static Future<bool> finalizeDownload(String fileName) async {
    return await DownloadManager.finalizeDownload(fileName);
  }

  /// Get all active download tasks
  static List<DownloadInfo> getActiveDownloads() {
    return DownloadManager.getActiveDownloads();
  }

  /// Check if a specific model file exists
  static Future<bool> checkModelExists(String modelName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelPath = '${appDir.path}/leap/$modelName';
      
      // Use cached file operations
      final fileInfo = await FileCache.getFileInfo(modelPath);
      
      LeapLogger.fileOp('check_model_exists', modelPath, 
        details: 'exists: ${fileInfo.exists}, size: ${fileInfo.sizeFormatted}');

      return fileInfo.exists && fileInfo.size > 0;
      
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
      final modelFiles = await BackgroundFileOps.listModelFiles(leapDirPath);
      
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

      // Use background file operations
      final deleted = await BackgroundFileOps.deleteFile(modelPath);
      
      if (deleted) {
        // Invalidate cache
        FileCache.invalidate(modelPath);
        
        // Update state if this was the loaded model
        if (_currentLoadedModel == fileName) {
          _currentLoadedModel = '';
          _isModelLoaded = false;
          LeapLogger.modelOp('Unloaded deleted model', modelName: fileName);
        }
        
        LeapLogger.fileOp('delete_model', modelPath, details: 'success');
        return true;
      }
      
      LeapLogger.warning('Failed to delete model (file may not exist): $fileName');
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
    
    // Cleanup file cache
    FileCache.clearCache();
    
    // Cleanup download manager
    DownloadManager.dispose();
    
    LeapLogger.info('FlutterLeapSdkService disposed');
  }
  
  /// Get service statistics for debugging
  static Map<String, dynamic> getStats() {
    final cacheStats = FileCache.getStats();
    final activeDownloads = DownloadManager.getActiveDownloads();
    
    return {
      'isModelLoaded': instance._isModelLoaded,
      'currentModel': instance._currentLoadedModel,
      'cacheStats': {
        'totalEntries': cacheStats.totalEntries,
        'expiredEntries': cacheStats.expiredEntries,
      },
      'activeDownloads': activeDownloads.length,
    };
  }
}

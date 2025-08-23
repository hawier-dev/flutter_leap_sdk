import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'exceptions.dart';
import 'leap_logger.dart';

class FlutterLeapSdkService {
  static const MethodChannel _channel = MethodChannel('flutter_leap_sdk');
  static const EventChannel _streamChannel = EventChannel(
    'flutter_leap_sdk_streaming',
  );

  // State management - replaced static with instance-based
  bool _isModelLoaded = false;
  String _currentLoadedModel = '';
  bool _isDownloaderInitialized = false;
  
  // Singleton instance
  static FlutterLeapSdkService? _instance;
  static FlutterLeapSdkService get instance {
    _instance ??= FlutterLeapSdkService._internal();
    return _instance!;
  }
  
  FlutterLeapSdkService._internal() {
    // Initialize logging
    LeapLogger.initialize();
    
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
  static Future<String> generateResponse(String message, {String? systemPrompt}) async {
    return await instance._generateResponse(message, systemPrompt: systemPrompt);
  }
  
  Future<String> _generateResponse(String message, {String? systemPrompt}) async {
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
  static Stream<String> generateResponseStream(String message, {String? systemPrompt}) async* {
    yield* instance._generateResponseStream(message, systemPrompt: systemPrompt);
  }
  
  Stream<String> _generateResponseStream(String message, {String? systemPrompt}) async* {
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

  /// Download a model with progress monitoring (1-second intervals)
  static Future<String?> downloadModel({
    String? modelUrl,
    String? modelName,
    Function(DownloadProgress)? onProgress,
  }) async {
    await _ensureDownloaderInitialized();

    try {
      final fileName = modelName ?? 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle';
      final tempFileName = '$fileName.temp';
      final url = modelUrl ?? availableModels[fileName]?.url ?? 
          'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-350M-8da4w_output_8da8w-seq_4096.bundle?download=true';

      final appDir = await getApplicationDocumentsDirectory();
      final leapDir = Directory('${appDir.path}/leap');

      if (!await leapDir.exists()) {
        await leapDir.create(recursive: true);
      }

      // Start download and return taskId
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        fileName: tempFileName,
        savedDir: leapDir.path,
        showNotification: false,
        openFileFromNotification: false,
      );

      // Set up progress monitoring if callback provided
      if (onProgress != null && taskId != null) {
        _monitorDownloadProgress(taskId, onProgress);
      }

      return taskId;
    } catch (e) {
      LeapLogger.error('Download failed', e);
      throw DownloadException('Failed to start download: $e', 'DOWNLOAD_ERROR');
    }
  }

  /// Monitor download progress for a specific task (1-second intervals)
  static void _monitorDownloadProgress(
    String taskId,
    Function(DownloadProgress) onProgress,
  ) {
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        await _ensureDownloaderInitialized();
        
        final tasks = await FlutterDownloader.loadTasks();
        final task = tasks?.firstWhere(
          (task) => task.taskId == taskId,
          orElse: () => throw StateError('Task not found'),
        );

        if (task == null) {
          timer.cancel();
          return;
        }

        final progress = task.progress;
        final status = task.status;
        final modelInfo = availableModels.values.first;
        final estimatedSizeMB = int.tryParse(modelInfo.size.replaceAll(RegExp(r'[^0-9]'), '')) ?? 350;
        final totalBytes = estimatedSizeMB * 1024 * 1024;
        final downloadedBytes = (totalBytes * progress / 100).round();

        // Simple speed estimation based on progress
        final speedMBs = progress > 0 ? (downloadedBytes / 1024 / 1024 / 10).toStringAsFixed(1) : '0.0';

        final downloadProgress = DownloadProgress(
          bytesDownloaded: downloadedBytes,
          totalBytes: totalBytes,
          percentage: progress.toDouble(),
          speed: '${speedMBs} MB/s',
        );

        onProgress(downloadProgress);

        if (status == DownloadTaskStatus.complete) {
          timer.cancel();
          await _finalizeDownload(taskId);
        } else if (status == DownloadTaskStatus.failed || 
                   status == DownloadTaskStatus.canceled) {
          timer.cancel();
        }
      } catch (e) {
        LeapLogger.error('Progress monitoring error', e);
        timer.cancel();
      }
    });
  }

  /// Initialize flutter_downloader
  static Future<void> _ensureDownloaderInitialized() async {
    if (!instance._isDownloaderInitialized) {
      await FlutterDownloader.initialize(debug: false, ignoreSsl: false);
      instance._isDownloaderInitialized = true;
      LeapLogger.info('Flutter downloader initialized');
    }
  }

  /// Finalize download by renaming temp file
  static Future<void> _finalizeDownload(String taskId) async {
    try {
      final tasks = await FlutterDownloader.loadTasks();
      final task = tasks?.firstWhere(
        (task) => task.taskId == taskId,
        orElse: () => throw StateError('Task not found'),
      );

      if (task?.filename?.endsWith('.temp') == true) {
        final tempPath = '${task!.savedDir}/${task.filename}';
        final finalPath = tempPath.replaceAll('.temp', '');
        
        final tempFile = File(tempPath);
        if (await tempFile.exists()) {
          await tempFile.rename(finalPath);
          LeapLogger.info('Download finalized: $finalPath');
        }
      }
    } catch (e) {
      LeapLogger.error('Failed to finalize download', e);
    }
  }

  /// Cancel download by taskId
  static Future<void> cancelDownload(String taskId) async {
    await FlutterDownloader.cancel(taskId: taskId);
  }

  /// Pause download by taskId
  static Future<void> pauseDownload(String taskId) async {
    await FlutterDownloader.pause(taskId: taskId);
  }

  /// Resume download by taskId
  static Future<String?> resumeDownload(String taskId) async {
    return await FlutterDownloader.resume(taskId: taskId);
  }

  /// Retry failed download by taskId
  static Future<String?> retryDownload(String taskId) async {
    try {
      return await FlutterDownloader.retry(taskId: taskId);
    } catch (e) {
      throw DownloadException('Failed to retry download: $e', 'RETRY_ERROR');
    }
  }

  /// Get download status for a taskId
  static Future<DownloadTaskStatus?> getDownloadStatus(String taskId) async {
    final tasks = await FlutterDownloader.loadTasks();
    final task = tasks?.firstWhere((t) => t.taskId == taskId, orElse: () => throw StateError('Not found'));
    return task?.status;
  }

  /// Get download progress for a taskId
  static Future<DownloadProgress?> getDownloadProgress(String taskId) async {
    final tasks = await FlutterDownloader.loadTasks();
    final task = tasks?.firstWhere((t) => t.taskId == taskId, orElse: () => throw StateError('Not found'));
    if (task == null) return null;
    
    return DownloadProgress(
      bytesDownloaded: task.progress * 10 * 1024 * 1024 ~/ 100,
      totalBytes: 10 * 1024 * 1024,
      percentage: task.progress.toDouble(),
    );
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

      // Use background file operations
      final file = File(modelPath);
      await file.delete();
      final success = true;
      
      if (success) {
        // Invalidate cache
        // File cache invalidation removed
        
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
    // Cleanup removed - using simple implementation
    
    LeapLogger.info('FlutterLeapSdkService disposed');
  }
  
  /// Get service statistics for debugging
  static Map<String, dynamic> getStats() {
    final cacheStats = {'totalEntries': 0, 'expiredEntries': 0};
    final activeDownloads = <String>[];
    
    return {
      'isModelLoaded': instance._isModelLoaded,
      'currentModel': instance._currentLoadedModel,
      'cacheStats': {
        'totalEntries': cacheStats['totalEntries'],
        'expiredEntries': cacheStats['expiredEntries'],
      },
      'activeDownloads': activeDownloads.length,
    };
  }
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'models.dart';
import 'exceptions.dart';

class FlutterLeapSdkService {
  static const MethodChannel _channel = MethodChannel('flutter_leap_sdk');
  static const EventChannel _streamChannel = EventChannel('flutter_leap_sdk_streaming');

  static bool _isModelLoaded = false;
  static String _currentLoadedModel = '';

  // Available LEAP models from Liquid AI
  static const Map<String, ModelInfo> availableModels = {
    'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle': ModelInfo(
      fileName: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
      displayName: 'LFM2-350M',
      size: '322 MB',
      url: 'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-350M-8da4w_output_8da8w-seq_4096.bundle?download=true',
    ),
    'LFM2-700M-8da4w_output_8da8w-seq_4096.bundle': ModelInfo(
      fileName: 'LFM2-700M-8da4w_output_8da8w-seq_4096.bundle',
      displayName: 'LFM2-700M',
      size: '610 MB',
      url: 'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-700M-8da4w_output_8da8w-seq_4096.bundle?download=true',
    ),
    'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle': ModelInfo(
      fileName: 'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle',
      displayName: 'LFM2-1.2B',
      size: '924 MB',
      url: 'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle?download=true',
    ),
  };

  static String get currentLoadedModel => _currentLoadedModel;
  static bool get isModelLoaded => _isModelLoaded;

  /// Load a model from the specified path
  static Future<String> loadModel({String? modelPath}) async {
    try {
      String fullPath;
      if (modelPath != null && modelPath.startsWith('/')) {
        fullPath = modelPath;
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = modelPath ?? 'model.bundle';
        fullPath = '${appDir.path}/leap/$fileName';
      }

      final String result = await _channel.invokeMethod('loadModel', {
        'modelPath': fullPath,
      });
      _isModelLoaded = true;
      _currentLoadedModel = fullPath.split('/').last;
      return result;
    } on PlatformException catch (e) {
      _isModelLoaded = false;
      throw ModelLoadingException('Failed to load model: ${e.message}', e.code);
    }
  }

  /// Unload the currently loaded model
  static Future<String> unloadModel() async {
    try {
      final String result = await _channel.invokeMethod('unloadModel');
      _isModelLoaded = false;
      _currentLoadedModel = '';
      return result;
    } on PlatformException catch (e) {
      throw FlutterLeapSdkException('Failed to unload model: ${e.message}', e.code);
    }
  }

  /// Check if a model is currently loaded
  static Future<bool> checkModelLoaded() async {
    try {
      final bool result = await _channel.invokeMethod('isModelLoaded');
      _isModelLoaded = result;
      return result;
    } on PlatformException catch (e) {
      throw FlutterLeapSdkException('Failed to check model status: ${e.message}', e.code);
    }
  }

  /// Generate a response using the loaded model
  static Future<String> generateResponse(String message) async {
    if (!_isModelLoaded) {
      throw const ModelNotLoadedException();
    }

    try {
      final String result = await _channel.invokeMethod('generateResponse', {
        'message': message,
      });
      return result;
    } on PlatformException catch (e) {
      throw GenerationException('Failed to generate response: ${e.message}', e.code);
    }
  }

  /// Generate a streaming response using the loaded model
  static Stream<String> generateResponseStream(String message) async* {
    if (!_isModelLoaded) {
      throw const ModelNotLoadedException();
    }

    try {
      await _channel.invokeMethod('generateResponseStream', {
        'message': message,
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
      throw GenerationException('Failed to generate streaming response: ${e.message}', e.code);
    }
  }

  /// Cancel active streaming
  static Future<void> cancelStreaming() async {
    try {
      await _channel.invokeMethod('cancelStreaming');
    } on PlatformException catch (e) {
      throw FlutterLeapSdkException('Failed to cancel streaming: ${e.message}', e.code);
    }
  }

  /// Download a model using flutter_downloader
  static Future<String?> downloadModel({
    String? modelUrl,
    String? modelName,
    Function(DownloadProgress)? onProgress,
  }) async {
    try {
      final fileName = modelName ?? 'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle';
      final tempFileName = '$fileName.temp';
      final url = modelUrl ?? availableModels[fileName]?.url ?? 
          'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle?download=true';

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
      throw DownloadException('Failed to start download: $e', 'DOWNLOAD_ERROR');
    }
  }

  /// Monitor download progress for a specific task
  static void _monitorDownloadProgress(String taskId, Function(DownloadProgress) onProgress) {
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final tasks = await FlutterDownloader.loadTasks();
        final task = tasks?.firstWhere((t) => t.taskId == taskId, orElse: () => throw Exception('Task not found'));
        
        if (task != null) {
          final progress = DownloadProgress(
            bytesDownloaded: task.progress,
            totalBytes: 100,
            percentage: task.progress.toDouble(),
          );
          
          onProgress(progress);
          
          // Stop monitoring when complete or failed
          if (task.status == DownloadTaskStatus.complete || 
              task.status == DownloadTaskStatus.failed ||
              task.status == DownloadTaskStatus.canceled) {
            timer.cancel();
          }
        }
      } catch (e) {
        timer.cancel();
      }
    });
  }

  /// Cancel download by taskId
  static Future<void> cancelDownload(String taskId) async {
    try {
      await FlutterDownloader.cancel(taskId: taskId);
    } catch (e) {
      throw DownloadException('Failed to cancel download: $e', 'CANCEL_ERROR');
    }
  }

  /// Pause download by taskId
  static Future<void> pauseDownload(String taskId) async {
    try {
      await FlutterDownloader.pause(taskId: taskId);
    } catch (e) {
      throw DownloadException('Failed to pause download: $e', 'PAUSE_ERROR');
    }
  }

  /// Resume download by taskId
  static Future<String?> resumeDownload(String taskId) async {
    try {
      return await FlutterDownloader.resume(taskId: taskId);
    } catch (e) {
      throw DownloadException('Failed to resume download: $e', 'RESUME_ERROR');
    }
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
    try {
      final tasks = await FlutterDownloader.loadTasks();
      final task = tasks?.firstWhere((t) => t.taskId == taskId, orElse: () => throw Exception('Task not found'));
      return task?.status;
    } catch (e) {
      return null;
    }
  }

  /// Get download progress for a taskId
  static Future<DownloadProgress?> getDownloadProgress(String taskId) async {
    try {
      final tasks = await FlutterDownloader.loadTasks();
      final task = tasks?.firstWhere((t) => t.taskId == taskId, orElse: () => throw Exception('Task not found'));
      
      if (task != null) {
        return DownloadProgress(
          bytesDownloaded: task.progress,
          totalBytes: 100,
          percentage: task.progress.toDouble(),
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Move completed download from temp file to final location
  static Future<bool> finalizeDownload(String fileName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tempFile = File('${appDir.path}/leap/$fileName.temp');
      final finalFile = File('${appDir.path}/leap/$fileName');

      if (await tempFile.exists()) {
        await tempFile.rename(finalFile.path);
        return true;
      }
      return false;
    } catch (e) {
      throw DownloadException('Failed to finalize download: $e', 'FINALIZE_ERROR');
    }
  }

  /// Get all active download tasks
  static Future<List<DownloadTask>> getActiveDownloads() async {
    try {
      final tasks = await FlutterDownloader.loadTasks();
      return tasks?.where((task) => 
        task.status == DownloadTaskStatus.running || 
        task.status == DownloadTaskStatus.paused
      ).toList() ?? [];
    } catch (e) {
      return [];
    }
  }

  /// Check if a specific model file exists
  static Future<bool> checkModelExists(String modelName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDir.path}/leap/$modelName');
      return await modelFile.exists();
    } catch (e) {
      throw FlutterLeapSdkException('Failed to check model existence: $e', 'CHECK_MODEL_ERROR');
    }
  }

  /// Get list of downloaded model filenames
  static Future<List<String>> getDownloadedModels() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final leapDir = Directory('${appDir.path}/leap');

      if (!await leapDir.exists()) {
        return [];
      }

      final files = await leapDir.list().toList();
      final modelFiles = files
          .whereType<File>()
          .where((file) => file.path.endsWith('.bundle'))
          .map((file) => file.path.split('/').last)
          .toList();

      return modelFiles;
    } catch (e) {
      throw FlutterLeapSdkException('Failed to get downloaded models: $e', 'GET_MODELS_ERROR');
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

  /// Download LFM2-350M model
  static Future<String?> downloadLFM2_350M({Function(DownloadProgress)? onProgress}) async {
    return downloadModel(
      modelName: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
      onProgress: onProgress,
    );
  }

  /// Download LFM2-700M model
  static Future<String?> downloadLFM2_700M({Function(DownloadProgress)? onProgress}) async {
    return downloadModel(
      modelName: 'LFM2-700M-8da4w_output_8da8w-seq_4096.bundle',
      onProgress: onProgress,
    );
  }

  /// Download LFM2-1.2B model
  static Future<String?> downloadLFM2_1_2B({Function(DownloadProgress)? onProgress}) async {
    return downloadModel(
      modelName: 'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle',
      onProgress: onProgress,
    );
  }

  /// Delete a downloaded model file
  static Future<bool> deleteModel(String fileName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDir.path}/leap/$fileName');

      if (await modelFile.exists()) {
        await modelFile.delete();

        if (_currentLoadedModel == fileName) {
          _currentLoadedModel = '';
          _isModelLoaded = false;
        }

        return true;
      }
      return false;
    } catch (e) {
      throw FlutterLeapSdkException('Failed to delete model: $e', 'DELETE_MODEL_ERROR');
    }
  }
}
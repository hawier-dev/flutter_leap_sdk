import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'models.dart';
import 'exceptions.dart';

class FlutterLeapSdkService {
  static const MethodChannel _channel = MethodChannel('flutter_leap_sdk');
  static const EventChannel _streamChannel = EventChannel(
    'flutter_leap_sdk_streaming',
  );

  static bool _isModelLoaded = false;
  static String _currentLoadedModel = '';
  static bool _isDownloaderInitialized = false;

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

  static String get currentLoadedModel => _currentLoadedModel;
  static bool get isModelLoaded => _isModelLoaded;

  /// Initialize flutter_downloader
  static Future<void> initialize() async {
    if (!_isDownloaderInitialized) {
      await FlutterDownloader.initialize(debug: false, ignoreSsl: false);
      _isDownloaderInitialized = true;
    }
  }

  /// Ensure downloader is initialized before any download operation
  static Future<void> _ensureDownloaderInitialized() async {
    if (!_isDownloaderInitialized) {
      await initialize();
    }
  }

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

      print('DEBUG: Loading model:');
      print('DEBUG: Model path: $fullPath');

      final modelFile = File(fullPath);
      final exists = await modelFile.exists();
      print('DEBUG: File exists: $exists');

      if (exists) {
        final fileSize = await modelFile.length();
        print('DEBUG: File size: ${fileSize} bytes');
      } else {
        print('DEBUG: File does not exist! Available files:');
        final appDir = await getApplicationDocumentsDirectory();
        final leapDir = Directory('${appDir.path}/leap');
        if (await leapDir.exists()) {
          final files = await leapDir.list().toList();
          for (var file in files) {
            print('DEBUG: - ${file.path}');
          }
        } else {
          print('DEBUG: Leap directory does not exist!');
        }
      }

      final String result = await _channel.invokeMethod('loadModel', {
        'modelPath': fullPath,
      });
      _isModelLoaded = true;
      _currentLoadedModel = fullPath.split('/').last;
      return result;
    } on PlatformException catch (e) {
      _isModelLoaded = false;
      print('DEBUG: Model loading failed: ${e.message} (code: ${e.code})');
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
      throw FlutterLeapSdkException(
        'Failed to unload model: ${e.message}',
        e.code,
      );
    }
  }

  /// Check if a model is currently loaded
  static Future<bool> checkModelLoaded() async {
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
      throw GenerationException(
        'Failed to generate response: ${e.message}',
        e.code,
      );
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

  /// Download a model using flutter_downloader
  static Future<String?> downloadModel({
    String? modelUrl,
    String? modelName,
    Function(DownloadProgress)? onProgress,
  }) async {
    await _ensureDownloaderInitialized();

    try {
      final fileName =
          modelName ?? 'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle';
      final tempFileName = '$fileName.temp';
      final url =
          modelUrl ??
          availableModels[fileName]?.url ??
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
  static void _monitorDownloadProgress(
    String taskId,
    Function(DownloadProgress) onProgress,
  ) {
    Timer.periodic(const Duration(milliseconds: 250), (timer) async {
      try {
        await _ensureDownloaderInitialized();
        final tasks = await FlutterDownloader.loadTasks();

        if (tasks == null || tasks.isEmpty) {
          print('DEBUG: No tasks found, cancelling timer');
          timer.cancel();
          return;
        }

        DownloadTask? task;
        try {
          task = tasks.firstWhere((t) => t.taskId == taskId);
        } catch (e) {
          task = null;
        }

        if (task == null) {
          print('DEBUG: Task $taskId not found, cancelling timer');
          timer.cancel();
          return;
        }

        print('DEBUG: Task status: ${task.status}, progress: ${task.progress}');

        final progress = DownloadProgress(
          bytesDownloaded: task.progress,
          totalBytes: 100,
          percentage: task.progress.toDouble(),
        );

        onProgress(progress);

        // Handle completion - finalize the download
        if (task.status == DownloadTaskStatus.complete) {
          timer.cancel();
          print('DEBUG: Download completed, starting finalization');
          try {
            // Notify that finalization is starting
            final finalizingProgress = DownloadProgress(
              bytesDownloaded: 100,
              totalBytes: 100,
              percentage: 100.0,
            );
            onProgress(finalizingProgress);

            // Extract original filename from temp filename
            final tempFileName = task.filename;
            print('DEBUG: Temp filename: $tempFileName');
            if (tempFileName != null && tempFileName.endsWith('.temp')) {
              final originalFileName = tempFileName.replaceAll('.temp', '');
              print('DEBUG: Finalizing to: $originalFileName');
              final success = await finalizeDownload(originalFileName);
              print('DEBUG: Finalization result: $success');

              // Send final completion progress
              final completionProgress = DownloadProgress(
                bytesDownloaded: 100,
                totalBytes: 100,
                percentage: 100.0,
              );
              onProgress(completionProgress);
            }
          } catch (e) {
            // Even if finalization fails, at least notify completion
            print('DEBUG: Failed to finalize download: $e');
          }
        }
        // Stop monitoring when failed or canceled
        else if (task.status == DownloadTaskStatus.failed ||
            task.status == DownloadTaskStatus.canceled) {
          print('DEBUG: Task failed or cancelled: ${task.status}');
          timer.cancel();
        }
      } catch (e) {
        print('DEBUG: Error in progress monitoring: $e');
        timer.cancel();
      }
    });
  }

  /// Cancel download by taskId
  static Future<void> cancelDownload(String taskId) async {
    await _ensureDownloaderInitialized();

    try {
      await FlutterDownloader.cancel(taskId: taskId);
    } catch (e) {
      throw DownloadException('Failed to cancel download: $e', 'CANCEL_ERROR');
    }
  }

  /// Pause download by taskId
  static Future<void> pauseDownload(String taskId) async {
    await _ensureDownloaderInitialized();

    try {
      await FlutterDownloader.pause(taskId: taskId);
    } catch (e) {
      throw DownloadException('Failed to pause download: $e', 'PAUSE_ERROR');
    }
  }

  /// Resume download by taskId
  static Future<String?> resumeDownload(String taskId) async {
    await _ensureDownloaderInitialized();

    try {
      return await FlutterDownloader.resume(taskId: taskId);
    } catch (e) {
      throw DownloadException('Failed to resume download: $e', 'RESUME_ERROR');
    }
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

  /// Get download status for a taskId
  static Future<DownloadTaskStatus?> getDownloadStatus(String taskId) async {
    await _ensureDownloaderInitialized();

    try {
      final tasks = await FlutterDownloader.loadTasks();
      if (tasks == null) return null;

      DownloadTask? task;
      try {
        task = tasks.firstWhere((t) => t.taskId == taskId);
      } catch (e) {
        return null;
      }

      return task.status;
    } catch (e) {
      return null;
    }
  }

  /// Get download progress for a taskId
  static Future<DownloadProgress?> getDownloadProgress(String taskId) async {
    await _ensureDownloaderInitialized();

    try {
      final tasks = await FlutterDownloader.loadTasks();
      if (tasks == null) return null;

      DownloadTask? task;
      try {
        task = tasks.firstWhere((t) => t.taskId == taskId);
      } catch (e) {
        return null;
      }

      return DownloadProgress(
        bytesDownloaded: task.progress,
        totalBytes: 100,
        percentage: task.progress.toDouble(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Move completed download from temp file to final location
  static Future<bool> finalizeDownload(String fileName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final leapDir = Directory('${appDir.path}/leap');
      final tempFile = File('${appDir.path}/leap/$fileName.temp');
      final finalFile = File('${appDir.path}/leap/$fileName');

      print('DEBUG: Finalizing download:');
      print('DEBUG: App directory: ${appDir.path}');
      print('DEBUG: LEAP directory exists: ${await leapDir.exists()}');
      print('DEBUG: Temp file: ${tempFile.path}');
      print('DEBUG: Final file: ${finalFile.path}');
      print('DEBUG: Temp file exists: ${await tempFile.exists()}');

      // List all files in leap directory for debugging
      if (await leapDir.exists()) {
        final files = await leapDir.list().toList();
        print('DEBUG: Files in leap directory:');
        for (var file in files) {
          if (file is File) {
            final size = await file.length();
            print('DEBUG: - ${file.path} (${size} bytes)');
          } else {
            print('DEBUG: - ${file.path} (directory)');
          }
        }
      }

      if (await tempFile.exists()) {
        final tempFileSize = await tempFile.length();
        print('DEBUG: Temp file size: ${tempFileSize} bytes');

        // Check if final file already exists
        if (await finalFile.exists()) {
          print('DEBUG: Final file already exists, deleting it first');
          await finalFile.delete();
        }

        await tempFile.rename(finalFile.path);
        print('DEBUG: File renamed successfully');

        // Verify the rename worked
        final finalExists = await finalFile.exists();
        print('DEBUG: Final file exists after rename: $finalExists');

        if (finalExists) {
          final finalFileSize = await finalFile.length();
          print('DEBUG: Final file size: ${finalFileSize} bytes');
        }

        return finalExists;
      } else {
        print('DEBUG: Temp file does not exist!');

        // Check if final file already exists (maybe it was already moved?)
        if (await finalFile.exists()) {
          final finalFileSize = await finalFile.length();
          print(
            'DEBUG: Final file already exists with size: ${finalFileSize} bytes',
          );
          return true;
        }

        return false;
      }
    } catch (e) {
      print('DEBUG: Error during finalization: $e');
      print('DEBUG: Error type: ${e.runtimeType}');
      print('DEBUG: Stack trace: ${StackTrace.current}');
      throw DownloadException(
        'Failed to finalize download: $e',
        'FINALIZE_ERROR',
      );
    }
  }

  /// Get all active download tasks
  static Future<List<DownloadTask>> getActiveDownloads() async {
    await _ensureDownloaderInitialized();

    try {
      final tasks = await FlutterDownloader.loadTasks();
      return tasks
              ?.where(
                (task) =>
                    task.status == DownloadTaskStatus.running ||
                    task.status == DownloadTaskStatus.paused,
              )
              .toList() ??
          [];
    } catch (e) {
      return [];
    }
  }

  /// Check if a specific model file exists
  static Future<bool> checkModelExists(String modelName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDir.path}/leap/$modelName');
      final exists = await modelFile.exists();

      print('DEBUG: Checking model existence:');
      print('DEBUG: Model path: ${modelFile.path}');
      print('DEBUG: File exists: $exists');

      if (exists) {
        final fileSize = await modelFile.length();
        print('DEBUG: File size: ${fileSize} bytes');
      }

      return exists;
    } catch (e) {
      print('DEBUG: Error checking model existence: $e');
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
      throw FlutterLeapSdkException(
        'Failed to delete model: $e',
        'DELETE_MODEL_ERROR',
      );
    }
  }
}

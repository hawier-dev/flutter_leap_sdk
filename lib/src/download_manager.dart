import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'exceptions.dart';
import 'chunked_file_ops.dart';
import 'file_cache.dart';
import 'leap_logger.dart';

/// Event-driven download manager that eliminates inefficient polling
/// Uses flutter_downloader callbacks and port communication for real-time updates
class DownloadManager {
  static const String _portName = 'leap_downloader_send_port';
  static ReceivePort? _port;
  static bool _isInitialized = false;
  
  // Track active downloads
  static final Map<String, DownloadInfo> _activeDownloads = {};
  static final Map<String, StreamController<DownloadProgress>> _progressControllers = {};
  
  /// Initialize download manager with callback-based progress monitoring
  static Future<void> initialize() async {
    if (_isInitialized) return;
    
    await FlutterDownloader.initialize(debug: false, ignoreSsl: false);
    
    // Set up isolate port for receiving download updates
    _port = ReceivePort();
    
    // Register the callback
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(_port!.sendPort, _portName);
    
    // Set up the flutter_downloader callback
    FlutterDownloader.registerCallback(_downloadCallback);
    
    // Listen for download updates
    _port!.listen(_handleDownloadUpdate);
    
    _isInitialized = true;
    LeapLogger.info('Download manager initialized with event-driven callbacks');
  }

  /// Download model with real-time progress updates
  static Future<String?> downloadModel({
    String? modelUrl,
    String? modelName,
    Function(DownloadProgress)? onProgress,
  }) async {
    await _ensureInitialized();
    
    try {
      final fileName = modelName ?? 'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle';
      final tempFileName = '$fileName.temp';
      
      // Get model info for proper URL and expected size
      final modelInfo = _getModelInfo(fileName);
      final url = modelUrl ?? modelInfo?.url ?? _getDefaultModelUrl();
      
      final appDir = await getApplicationDocumentsDirectory();
      final leapDir = Directory('${appDir.path}/leap');
      
      if (!await leapDir.exists()) {
        await leapDir.create(recursive: true);
      }
      
      LeapLogger.info('Starting download: $fileName');
      LeapLogger.info('URL: $url');
      LeapLogger.info('Expected size: ${modelInfo?.size ?? 'Unknown'}');
      
      // Start download
      final taskId = await FlutterDownloader.enqueue(
        url: url,
        fileName: tempFileName,
        savedDir: leapDir.path,
        showNotification: false,
        openFileFromNotification: false,
        requiresStorageNotLow: true,
        saveInPublicStorage: false,
      );
      
      if (taskId == null) {
        throw DownloadException('Failed to start download', 'ENQUEUE_FAILED');
      }
      
      // Set up progress monitoring for this download
      final downloadInfo = DownloadInfo(
        taskId: taskId,
        fileName: fileName,
        tempFileName: tempFileName,
        expectedSize: _parseSize(modelInfo?.size),
        onProgress: onProgress,
      );
      
      _activeDownloads[taskId] = downloadInfo;
      
      // Create progress stream controller
      final controller = StreamController<DownloadProgress>.broadcast();
      _progressControllers[taskId] = controller;
      
      // Set up stream listener for progress callback
      if (onProgress != null) {
        controller.stream.listen(onProgress);
      }
      
      LeapLogger.info('Download started with task ID: $taskId');
      return taskId;
      
    } catch (e) {
      LeapLogger.error('Failed to start download', e);
      throw DownloadException('Failed to start download: $e', 'DOWNLOAD_ERROR');
    }
  }
  
  /// Cancel download by taskId
  static Future<void> cancelDownload(String taskId) async {
    await _ensureInitialized();
    
    try {
      await FlutterDownloader.cancel(taskId: taskId);
      _cleanupDownload(taskId);
      LeapLogger.info('Download cancelled: $taskId');
    } catch (e) {
      LeapLogger.error('Failed to cancel download: $taskId', e);
      throw DownloadException('Failed to cancel download: $e', 'CANCEL_ERROR');
    }
  }
  
  /// Pause download by taskId
  static Future<void> pauseDownload(String taskId) async {
    await _ensureInitialized();
    
    try {
      await FlutterDownloader.pause(taskId: taskId);
      LeapLogger.info('Download paused: $taskId');
    } catch (e) {
      LeapLogger.error('Failed to pause download: $taskId', e);
      throw DownloadException('Failed to pause download: $e', 'PAUSE_ERROR');
    }
  }
  
  /// Resume download by taskId
  static Future<String?> resumeDownload(String taskId) async {
    await _ensureInitialized();
    
    try {
      final newTaskId = await FlutterDownloader.resume(taskId: taskId);
      if (newTaskId != null && newTaskId != taskId) {
        // Update tracking with new task ID
        final downloadInfo = _activeDownloads.remove(taskId);
        if (downloadInfo != null) {
          _activeDownloads[newTaskId] = downloadInfo.copyWith(taskId: newTaskId);
          
          final controller = _progressControllers.remove(taskId);
          if (controller != null) {
            _progressControllers[newTaskId] = controller;
          }
        }
      }
      
      LeapLogger.info('Download resumed: $taskId -> ${newTaskId ?? taskId}');
      return newTaskId;
    } catch (e) {
      LeapLogger.error('Failed to resume download: $taskId', e);
      throw DownloadException('Failed to resume download: $e', 'RESUME_ERROR');
    }
  }
  
  /// Get current download progress for a task
  static Future<DownloadProgress?> getDownloadProgress(String taskId) async {
    await _ensureInitialized();
    
    try {
      final tasks = await FlutterDownloader.loadTasks();
      if (tasks == null) return null;
      
      final task = tasks.where((t) => t.taskId == taskId).firstOrNull;
      if (task == null) return null;
      
      final downloadInfo = _activeDownloads[taskId];
      final expectedSize = downloadInfo?.expectedSize ?? 100;
      
      return DownloadProgress(
        bytesDownloaded: (task.progress * expectedSize / 100).round(),
        totalBytes: expectedSize,
        percentage: task.progress.toDouble(),
      );
    } catch (e) {
      LeapLogger.error('Failed to get download progress: $taskId', e);
      return null;
    }
  }
  
  /// Get all active downloads
  static List<DownloadInfo> getActiveDownloads() {
    return _activeDownloads.values.toList();
  }
  
  /// Clean up completed or cancelled downloads
  static void _cleanupDownload(String taskId) {
    _activeDownloads.remove(taskId);
    final controller = _progressControllers.remove(taskId);
    controller?.close();
  }
  
  /// Finalize download using chunked file operations
  static Future<bool> finalizeDownload(String fileName) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tempFile = File('${appDir.path}/leap/$fileName.temp');
      final finalFile = File('${appDir.path}/leap/$fileName');
      
      LeapLogger.info('Finalizing download: $fileName');
      
      if (!(await tempFile.exists())) {
        LeapLogger.error('Temp file does not exist: ${tempFile.path}');
        return false;
      }
      
      // Use chunked file operations for large files
      final success = await ChunkedFileOps.moveFileChunked(
        tempFile,
        finalFile,
        onProgress: (progress) {
          LeapLogger.debug('Finalization progress: ${(progress * 100).toStringAsFixed(1)}%');
        },
      );
      
      if (success) {
        // Invalidate cache for this file
        FileCache.invalidate(finalFile.path);
        LeapLogger.info('Download finalized successfully: $fileName');
      } else {
        LeapLogger.error('Failed to finalize download: $fileName');
      }
      
      return success;
      
    } catch (e) {
      LeapLogger.error('Error during download finalization: $fileName', e);
      throw DownloadException('Failed to finalize download: $e', 'FINALIZE_ERROR');
    }
  }
  
  // Private methods
  static Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }
  
  /// Flutter downloader callback - runs in isolate
  static void _downloadCallback(String id, DownloadTaskStatus status, int progress) {
    final SendPort? send = IsolateNameServer.lookupPortByName(_portName);
    send?.send([id, status.index, progress]);
  }
  
  /// Handle download updates from isolate callback
  static void _handleDownloadUpdate(dynamic data) async {
    if (data is! List || data.length != 3) return;
    
    final String taskId = data[0];
    final int statusIndex = data[1];
    final int progress = data[2];
    
    final status = DownloadTaskStatus.values[statusIndex];
    final downloadInfo = _activeDownloads[taskId];
    final controller = _progressControllers[taskId];
    
    if (downloadInfo == null || controller == null) {
      return; // Download not tracked or already cleaned up
    }
    
    LeapLogger.downloadProgress(
      downloadInfo.fileName, 
      progress / 100.0,
      bytesDownloaded: (progress * (downloadInfo.expectedSize ?? 100) / 100).round(),
      totalBytes: downloadInfo.expectedSize,
    );
    
    // Create progress update
    final progressUpdate = DownloadProgress(
      bytesDownloaded: (progress * (downloadInfo.expectedSize ?? 100) / 100).round(),
      totalBytes: downloadInfo.expectedSize ?? 100,
      percentage: progress.toDouble(),
    );
    
    // Send progress update
    if (!controller.isClosed) {
      controller.add(progressUpdate);
    }
    
    // Handle completion
    if (status == DownloadTaskStatus.complete) {
      LeapLogger.info('Download completed: ${downloadInfo.fileName}');
      
      try {
        // Finalize download
        final success = await finalizeDownload(downloadInfo.fileName);
        
        // Send final completion update
        if (!controller.isClosed) {
          controller.add(DownloadProgress(
            bytesDownloaded: downloadInfo.expectedSize ?? 100,
            totalBytes: downloadInfo.expectedSize ?? 100,
            percentage: 100.0,
          ));
        }
        
        if (success) {
          LeapLogger.info('Download and finalization completed: ${downloadInfo.fileName}');
        }
        
      } catch (e) {
        LeapLogger.error('Failed to finalize download: ${downloadInfo.fileName}', e);
      }
      
      _cleanupDownload(taskId);
    }
    // Handle failure or cancellation
    else if (status == DownloadTaskStatus.failed || status == DownloadTaskStatus.canceled) {
      LeapLogger.warning('Download ${status.name}: ${downloadInfo.fileName}');
      _cleanupDownload(taskId);
    }
  }
  
  static ModelInfo? _getModelInfo(String fileName) {
    // This would be moved from FlutterLeapSdkService.availableModels
    const availableModels = {
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
    
    return availableModels[fileName];
  }
  
  static String _getDefaultModelUrl() {
    return 'https://huggingface.co/LiquidAI/LeapBundles/resolve/main/LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle?download=true';
  }
  
  static int? _parseSize(String? sizeStr) {
    if (sizeStr == null) return null;
    
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*(MB|GB|KB|B)', caseSensitive: false).firstMatch(sizeStr);
    if (match == null) return null;
    
    final value = double.parse(match.group(1)!);
    final unit = match.group(2)!.toUpperCase();
    
    switch (unit) {
      case 'B': return value.round();
      case 'KB': return (value * 1024).round();
      case 'MB': return (value * 1024 * 1024).round();
      case 'GB': return (value * 1024 * 1024 * 1024).round();
      default: return null;
    }
  }
  
  /// Cleanup resources
  static void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
    _activeDownloads.clear();
    
    _port?.close();
    _port = null;
    
    IsolateNameServer.removePortNameMapping(_portName);
    _isInitialized = false;
  }
}

/// Information about an active download
class DownloadInfo {
  final String taskId;
  final String fileName;
  final String tempFileName;
  final int? expectedSize;
  final Function(DownloadProgress)? onProgress;
  
  const DownloadInfo({
    required this.taskId,
    required this.fileName,
    required this.tempFileName,
    this.expectedSize,
    this.onProgress,
  });
  
  DownloadInfo copyWith({
    String? taskId,
    String? fileName,
    String? tempFileName,
    int? expectedSize,
    Function(DownloadProgress)? onProgress,
  }) {
    return DownloadInfo(
      taskId: taskId ?? this.taskId,
      fileName: fileName ?? this.fileName,
      tempFileName: tempFileName ?? this.tempFileName,
      expectedSize: expectedSize ?? this.expectedSize,
      onProgress: onProgress ?? this.onProgress,
    );
  }
  
  @override
  String toString() {
    return 'DownloadInfo(taskId: $taskId, fileName: $fileName, expectedSize: $expectedSize)';
  }
}

// Extension to get first element or null
extension IterableExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
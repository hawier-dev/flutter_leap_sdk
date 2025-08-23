import 'package:flutter/foundation.dart';

/// Secure logging system for Flutter LEAP SDK
/// Prevents sensitive information leakage in production builds
class LeapLogger {
  static bool _isInitialized = false;
  static LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.warning;
  
  /// Initialize logger with custom settings
  static void initialize({
    LogLevel? minLevel,
    bool? enableFileLogging,
  }) {
    if (minLevel != null) {
      _minLevel = minLevel;
    }
    _isInitialized = true;
  }
  
  /// Set minimum log level
  static void setLevel(LogLevel level) {
    _minLevel = level;
  }
  
  /// Debug level logging (only in debug builds)
  static void debug(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.debug, message, error, stackTrace);
  }
  
  /// Info level logging
  static void info(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.info, message, error, stackTrace);
  }
  
  /// Warning level logging
  static void warning(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.warning, message, error, stackTrace);
  }
  
  /// Error level logging
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, error, stackTrace);
  }
  
  /// Critical error logging
  static void critical(String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.critical, message, error, stackTrace);
  }
  
  /// Log file operation with sanitized paths
  static void fileOp(String operation, String path, {String? details}) {
    if (!_shouldLog(LogLevel.debug)) return;
    
    final sanitizedPath = _sanitizeFilePath(path);
    final message = 'FileOp: $operation -> $sanitizedPath';
    
    if (details != null) {
      debug('$message ($details)');
    } else {
      debug(message);
    }
  }
  
  /// Log download progress
  static void downloadProgress(String modelName, double progress, {int? bytesDownloaded, int? totalBytes}) {
    if (!_shouldLog(LogLevel.info)) return;
    
    final progressPercent = (progress * 100).toStringAsFixed(1);
    var message = 'Download: $modelName -> $progressPercent%';
    
    if (bytesDownloaded != null && totalBytes != null) {
      final downloaded = _formatBytes(bytesDownloaded);
      final total = _formatBytes(totalBytes);
      message += ' ($downloaded / $total)';
    }
    
    info(message);
  }
  
  /// Log model operations
  static void modelOp(String operation, {String? modelName, String? details}) {
    if (!_shouldLog(LogLevel.info)) return;
    
    var message = 'ModelOp: $operation';
    if (modelName != null) {
      message += ' -> $modelName';
    }
    if (details != null) {
      message += ' ($details)';
    }
    
    info(message);
  }
  
  // Private methods
  static void _log(LogLevel level, String message, Object? error, StackTrace? stackTrace) {
    if (!_shouldLog(level)) return;
    
    final timestamp = DateTime.now();
    final levelStr = level.name.toUpperCase().padRight(8);
    final logMessage = '${_formatTimestamp(timestamp)} $levelStr [LEAP] $message';
    
    // In debug mode, use print for immediate visibility
    if (kDebugMode) {
      print(logMessage);
      
      if (error != null) {
        print('${_formatTimestamp(timestamp)} ERROR    [LEAP] Exception: $error');
      }
      
      if (stackTrace != null) {
        print('${_formatTimestamp(timestamp)} STACK    [LEAP] $stackTrace');
      }
    }
    
    // In release mode, only log critical errors to system log
    if (!kDebugMode && (level == LogLevel.error || level == LogLevel.critical)) {
      // This could be extended to send to crash reporting service
      debugPrint(logMessage);
    }
  }
  
  static bool _shouldLog(LogLevel level) {
    return level.index >= _minLevel.index;
  }
  
  static String _formatTimestamp(DateTime timestamp) {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
           '${timestamp.minute.toString().padLeft(2, '0')}:'
           '${timestamp.second.toString().padLeft(2, '0')}.'
           '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }
  
  static String _sanitizeFilePath(String path) {
    if (!kDebugMode) {
      // In production, only show filename and hide sensitive directories
      final parts = path.split('/');
      if (parts.isNotEmpty) {
        return '***/${parts.last}';
      }
      return '***';
    }
    
    // In debug mode, show partial path but hide user-specific directories
    return path
        .replaceAll(RegExp(r'/data/data/[^/]+/'), '/***/')
        .replaceAll(RegExp(r'/storage/emulated/[0-9]+/'), '/***/')
        .replaceAll(RegExp(r'/Users/[^/]+/'), '/***/')
        .replaceAll(RegExp(r'/home/[^/]+/'), '/***/')
        .replaceAll(RegExp(r'C:\\Users\\[^\\]+\\'), 'C:\\***\\');
  }
  
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
  }
}

/// Log levels in order of severity
enum LogLevel {
  debug,    // Detailed debugging information (debug builds only)
  info,     // General information
  warning,  // Warning conditions
  error,    // Error conditions
  critical, // Critical errors that might cause app instability
}

/// Extension to get log level names
extension LogLevelExtension on LogLevel {
  String get name {
    switch (this) {
      case LogLevel.debug:
        return 'debug';
      case LogLevel.info:
        return 'info';
      case LogLevel.warning:
        return 'warning';
      case LogLevel.error:
        return 'error';
      case LogLevel.critical:
        return 'critical';
    }
  }
}
import 'dart:io';
import 'background_file_ops.dart';
import 'leap_logger.dart';

/// Smart file caching system to avoid repeated I/O operations
/// Caches file existence, size, and modification times with automatic expiry
class FileCache {
  static final Map<String, _FileCacheEntry> _cache = {};
  static const Duration _defaultCacheExpiry = Duration(minutes: 5);
  static const Duration _quickCacheExpiry = Duration(seconds: 30);
  
  /// Get cached file size or fetch from background if expired
  static Future<int> getFileSize(String path, {Duration? cacheExpiry}) async {
    final expiry = cacheExpiry ?? _defaultCacheExpiry;
    final cached = _getCachedEntry(path, expiry);
    
    if (cached?.size != null) {
      LeapLogger.debug('Cache hit for file size: $path');
      return cached!.size!;
    }
    
    LeapLogger.debug('Cache miss for file size: $path');
    final size = await BackgroundFileOps.getFileSize(path);
    _updateCacheEntry(path, size: size);
    
    return size;
  }
  
  /// Get cached file existence or fetch from background if expired
  static Future<bool> fileExists(String path, {Duration? cacheExpiry}) async {
    final expiry = cacheExpiry ?? _defaultCacheExpiry;
    final cached = _getCachedEntry(path, expiry);
    
    if (cached?.exists != null) {
      LeapLogger.debug('Cache hit for file exists: $path');
      return cached!.exists!;
    }
    
    LeapLogger.debug('Cache miss for file exists: $path');
    final exists = await BackgroundFileOps.fileExists(path);
    _updateCacheEntry(path, exists: exists);
    
    return exists;
  }
  
  /// Get cached file stat or fetch from background if expired
  static Future<FileStat?> getFileStat(String path, {Duration? cacheExpiry}) async {
    final expiry = cacheExpiry ?? _defaultCacheExpiry;
    final cached = _getCachedEntry(path, expiry);
    
    if (cached?.stat != null) {
      LeapLogger.debug('Cache hit for file stat: $path');
      return cached!.stat!;
    }
    
    LeapLogger.debug('Cache miss for file stat: $path');
    final stat = await BackgroundFileOps.getFileStat(path);
    _updateCacheEntry(path, stat: stat);
    
    return stat;
  }
  
  /// Get file info (size + exists + stat) efficiently
  static Future<FileInfo> getFileInfo(String path, {Duration? cacheExpiry}) async {
    final expiry = cacheExpiry ?? _defaultCacheExpiry;
    final cached = _getCachedEntry(path, expiry);
    
    if (cached != null && 
        cached.exists != null && 
        cached.size != null &&
        cached.stat != null) {
      LeapLogger.debug('Cache hit for full file info: $path');
      return FileInfo(
        exists: cached.exists!,
        size: cached.size!,
        stat: cached.stat,
      );
    }
    
    LeapLogger.debug('Cache miss for full file info: $path');
    
    // Fetch all info in parallel
    final futures = await Future.wait([
      BackgroundFileOps.fileExists(path),
      BackgroundFileOps.getFileSize(path),
      BackgroundFileOps.getFileStat(path),
    ]);
    
    final exists = futures[0] as bool;
    final size = futures[1] as int;
    final stat = futures[2] as FileStat?;
    
    _updateCacheEntry(path, exists: exists, size: size, stat: stat);
    
    return FileInfo(exists: exists, size: size, stat: stat);
  }
  
  /// Invalidate cache entry for a specific path
  static void invalidate(String path) {
    _cache.remove(path);
    LeapLogger.debug('Cache invalidated for: $path');
  }
  
  /// Invalidate cache entries matching pattern
  static void invalidatePattern(String pattern) {
    final keys = _cache.keys.where((key) => key.contains(pattern)).toList();
    for (final key in keys) {
      _cache.remove(key);
    }
    LeapLogger.debug('Cache invalidated for pattern: $pattern (${keys.length} entries)');
  }
  
  /// Clear entire cache
  static void clearCache() {
    final count = _cache.length;
    _cache.clear();
    LeapLogger.debug('Cache cleared: $count entries removed');
  }
  
  /// Get cache statistics
  static CacheStats getStats() {
    int totalEntries = _cache.length;
    int expiredEntries = 0;
    final now = DateTime.now();
    
    for (final entry in _cache.values) {
      if (now.difference(entry.timestamp) > _defaultCacheExpiry) {
        expiredEntries++;
      }
    }
    
    return CacheStats(
      totalEntries: totalEntries,
      expiredEntries: expiredEntries,
      hitRatio: 0.0, // Could track this with counters
    );
  }
  
  /// Clean up expired cache entries
  static void cleanupExpired() {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    
    for (final entry in _cache.entries) {
      if (now.difference(entry.value.timestamp) > _defaultCacheExpiry) {
        keysToRemove.add(entry.key);
      }
    }
    
    for (final key in keysToRemove) {
      _cache.remove(key);
    }
    
    if (keysToRemove.isNotEmpty) {
      LeapLogger.debug('Cache cleanup: removed ${keysToRemove.length} expired entries');
    }
  }
  
  // Private helper methods
  static _FileCacheEntry? _getCachedEntry(String path, Duration expiry) {
    final cached = _cache[path];
    if (cached == null) return null;
    
    final now = DateTime.now();
    if (now.difference(cached.timestamp) > expiry) {
      _cache.remove(path);
      return null;
    }
    
    return cached;
  }
  
  static void _updateCacheEntry(
    String path, {
    bool? exists,
    int? size,
    FileStat? stat,
  }) {
    final existing = _cache[path];
    final now = DateTime.now();
    
    _cache[path] = _FileCacheEntry(
      exists: exists ?? existing?.exists,
      size: size ?? existing?.size,
      stat: stat ?? existing?.stat,
      timestamp: now,
    );
  }
}

/// Internal cache entry class
class _FileCacheEntry {
  final bool? exists;
  final int? size;
  final FileStat? stat;
  final DateTime timestamp;
  
  const _FileCacheEntry({
    this.exists,
    this.size,
    this.stat,
    required this.timestamp,
  });
}

/// File information container
class FileInfo {
  final bool exists;
  final int size;
  final FileStat? stat;
  
  const FileInfo({
    required this.exists,
    required this.size,
    this.stat,
  });
  
  DateTime? get lastModified => stat?.modified;
  DateTime? get lastAccessed => stat?.accessed;
  DateTime? get created => stat?.changed;
  
  String get sizeFormatted {
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    if (size < 1024 * 1024 * 1024) return '${(size / 1024 / 1024).toStringAsFixed(1)}MB';
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)}GB';
  }
  
  @override
  String toString() {
    return 'FileInfo(exists: $exists, size: $sizeFormatted, modified: $lastModified)';
  }
}

/// Cache statistics container
class CacheStats {
  final int totalEntries;
  final int expiredEntries;
  final double hitRatio;
  
  const CacheStats({
    required this.totalEntries,
    required this.expiredEntries,
    required this.hitRatio,
  });
  
  int get validEntries => totalEntries - expiredEntries;
  
  @override
  String toString() {
    return 'CacheStats(total: $totalEntries, valid: $validEntries, expired: $expiredEntries, hitRatio: ${(hitRatio * 100).toStringAsFixed(1)}%)';
  }
}
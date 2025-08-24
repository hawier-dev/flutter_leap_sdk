import 'dart:convert';

/// Information about a LEAP SDK model bundle.
///
/// Contains metadata for downloadable LFM2 models including file details,
/// display name, estimated size, and download URL.
class ModelInfo {
  /// The actual filename of the model bundle
  final String fileName;

  /// Human-readable display name for the model
  final String displayName;

  /// Estimated size of the model (e.g., "322 MB")
  final String size;

  /// Direct download URL for the model bundle
  final String url;

  const ModelInfo({
    required this.fileName,
    required this.displayName,
    required this.size,
    required this.url,
  });

  Map<String, dynamic> toMap() {
    return {
      'fileName': fileName,
      'displayName': displayName,
      'size': size,
      'url': url,
    };
  }

  factory ModelInfo.fromMap(Map<String, dynamic> map) {
    return ModelInfo(
      fileName: map['fileName'] ?? '',
      displayName: map['displayName'] ?? '',
      size: map['size'] ?? '',
      url: map['url'] ?? '',
    );
  }

  @override
  String toString() {
    return 'ModelInfo(fileName: $fileName, displayName: $displayName, size: $size, url: $url)';
  }
}

/// Represents the progress of a model download operation.
///
/// Tracks download progress with bytes downloaded, total bytes, percentage, and speed.
/// Used in download progress callbacks to provide real-time download status.
class DownloadProgress {
  /// Number of bytes successfully downloaded
  final int bytesDownloaded;

  /// Total size of the download in bytes
  final int totalBytes;

  /// Percentage of download completed (0.0 to 100.0)
  final double percentage;

  /// Current download speed as a formatted string
  final String speed;

  const DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.percentage,
    this.speed = '',
  });

  /// Alias for bytesDownloaded for backward compatibility
  int get downloaded => bytesDownloaded;
  
  /// Alias for totalBytes for backward compatibility
  int get total => totalBytes;

  bool get isComplete => percentage >= 100.0;

  @override
  String toString() {
    return 'DownloadProgress(bytesDownloaded: $bytesDownloaded, totalBytes: $totalBytes, percentage: ${percentage.toStringAsFixed(1)}%, speed: $speed)';
  }
}

/// Enum defining the role of a message in a conversation.
/// 
/// Corresponds to the roles used in the native LEAP SDK for structured conversations.
enum MessageRole {
  /// System message - provides instructions or context for the AI
  system,
  /// User message - input from the human user
  user, 
  /// Assistant message - response from the AI model
  assistant
}

/// Represents a single message in a conversation with role and content.
///
/// This mirrors the ChatMessage structure in the native LEAP SDKs,
/// allowing for proper conversation management with role-based interactions.
class ChatMessage {
  /// The role of this message (system, user, or assistant)
  final MessageRole role;
  
  /// The text content of the message
  final String content;
  
  /// Optional reasoning content (for assistant messages with reasoning)
  final String? reasoningContent;
  
  /// Timestamp when this message was created
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    this.reasoningContent,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create a system message
  factory ChatMessage.system(String content) {
    return ChatMessage(role: MessageRole.system, content: content);
  }

  /// Create a user message
  factory ChatMessage.user(String content) {
    return ChatMessage(role: MessageRole.user, content: content);
  }

  /// Create an assistant message
  factory ChatMessage.assistant(String content, {String? reasoningContent}) {
    return ChatMessage(
      role: MessageRole.assistant, 
      content: content,
      reasoningContent: reasoningContent,
    );
  }

  /// Convert to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'role': role.name,
      'content': content,
      'reasoningContent': reasoningContent,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Create from map for deserialization
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      role: MessageRole.values.firstWhere((r) => r.name == map['role']),
      content: map['content'] ?? '',
      reasoningContent: map['reasoningContent'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
    );
  }

  /// Convert to JSON string
  String toJson() => json.encode(toMap());

  /// Create from JSON string
  factory ChatMessage.fromJson(String jsonString) => 
      ChatMessage.fromMap(json.decode(jsonString));

  @override
  String toString() {
    return 'ChatMessage(role: ${role.name}, content: "$content"${reasoningContent != null ? ', reasoning: "$reasoningContent"' : ''})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage &&
        other.role == role &&
        other.content == content &&
        other.reasoningContent == reasoningContent;
  }

  @override
  int get hashCode => Object.hash(role, content, reasoningContent);
}

/// Configuration options for text generation.
///
/// Controls various parameters that affect how the model generates responses,
/// corresponding to GenerationOptions in the native LEAP SDKs.
class GenerationOptions {
  /// Controls randomness in generation (0.0 to 2.0)
  /// - Lower values (e.g., 0.1) make output more focused and deterministic
  /// - Higher values (e.g., 1.5) make output more creative and varied
  final double? temperature;

  /// Nucleus sampling parameter (0.0 to 1.0)
  /// Controls diversity by limiting to tokens with cumulative probability <= topP
  final double? topP;

  /// Minimum probability threshold (0.0 to 1.0)
  /// Tokens with probability below this threshold are filtered out
  final double? minP;

  /// Penalty for repeating tokens (0.0 to 2.0)
  /// Values > 1.0 discourage repetition, values < 1.0 encourage it
  final double? repetitionPenalty;

  /// Maximum number of tokens to generate
  /// If null, uses model's default limit
  final int? maxTokens;

  /// Optional JSON schema to constrain generation format
  /// When provided, forces model to generate valid JSON matching the schema
  final Map<String, dynamic>? jsonSchema;

  const GenerationOptions({
    this.temperature,
    this.topP,
    this.minP,
    this.repetitionPenalty,
    this.maxTokens,
    this.jsonSchema,
  });

  /// Create with creative settings (higher temperature, more diverse)
  factory GenerationOptions.creative() {
    return const GenerationOptions(
      temperature: 1.2,
      topP: 0.95,
      repetitionPenalty: 1.1,
    );
  }

  /// Create with precise settings (lower temperature, more focused)
  factory GenerationOptions.precise() {
    return const GenerationOptions(
      temperature: 0.3,
      topP: 0.8,
      repetitionPenalty: 1.15,
    );
  }

  /// Create with balanced settings (default recommended values)
  factory GenerationOptions.balanced() {
    return const GenerationOptions(
      temperature: 0.7,
      topP: 0.9,
      repetitionPenalty: 1.1,
    );
  }

  /// Convert to map for native method calls
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    
    if (temperature != null) map['temperature'] = temperature;
    if (topP != null) map['topP'] = topP;
    if (minP != null) map['minP'] = minP;
    if (repetitionPenalty != null) map['repetitionPenalty'] = repetitionPenalty;
    if (maxTokens != null) map['maxTokens'] = maxTokens;
    if (jsonSchema != null) map['jsonSchema'] = jsonSchema;
    
    return map;
  }

  /// Create from map
  factory GenerationOptions.fromMap(Map<String, dynamic> map) {
    return GenerationOptions(
      temperature: map['temperature']?.toDouble(),
      topP: map['topP']?.toDouble(),
      minP: map['minP']?.toDouble(),
      repetitionPenalty: map['repetitionPenalty']?.toDouble(),
      maxTokens: map['maxTokens']?.toInt(),
      jsonSchema: map['jsonSchema'],
    );
  }

  @override
  String toString() {
    final parts = <String>[];
    if (temperature != null) parts.add('temperature: $temperature');
    if (topP != null) parts.add('topP: $topP');
    if (minP != null) parts.add('minP: $minP');
    if (repetitionPenalty != null) parts.add('repetitionPenalty: $repetitionPenalty');
    if (maxTokens != null) parts.add('maxTokens: $maxTokens');
    if (jsonSchema != null) parts.add('jsonSchema: ${jsonSchema.toString()}');
    
    return 'GenerationOptions(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GenerationOptions &&
        other.temperature == temperature &&
        other.topP == topP &&
        other.minP == minP &&
        other.repetitionPenalty == repetitionPenalty &&
        other.maxTokens == maxTokens &&
        other.jsonSchema == jsonSchema;
  }

  @override
  int get hashCode => Object.hash(
        temperature,
        topP,
        minP,
        repetitionPenalty,
        maxTokens,
        jsonSchema,
      );
}

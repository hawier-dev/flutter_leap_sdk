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
  
  /// Function calls associated with this message
  final List<LeapFunctionCall>? functionCalls;
  
  /// Timestamp when this message was created
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    this.reasoningContent,
    this.functionCalls,
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
  factory ChatMessage.assistant(String content, {String? reasoningContent, List<LeapFunctionCall>? functionCalls}) {
    return ChatMessage(
      role: MessageRole.assistant, 
      content: content,
      reasoningContent: reasoningContent,
      functionCalls: functionCalls,
    );
  }

  /// Convert to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'role': role.name,
      'content': content,
      'reasoningContent': reasoningContent,
      'functionCalls': functionCalls?.map((fc) => fc.toMap()).toList(),
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Create from map for deserialization
  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      role: MessageRole.values.firstWhere((r) => r.name == map['role']),
      content: map['content'] ?? '',
      reasoningContent: map['reasoningContent'],
      functionCalls: map['functionCalls'] != null
          ? (map['functionCalls'] as List).map((fc) => LeapFunctionCall.fromMap(fc)).toList()
          : null,
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
    final parts = ['role: ${role.name}', 'content: "$content"'];
    if (reasoningContent != null) parts.add('reasoning: "$reasoningContent"');
    if (functionCalls != null && functionCalls!.isNotEmpty) parts.add('functionCalls: ${functionCalls!.length}');
    return 'ChatMessage(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ChatMessage &&
        other.role == role &&
        other.content == content &&
        other.reasoningContent == reasoningContent &&
        _functionCallsEqual(other.functionCalls, functionCalls);
  }

  @override
  int get hashCode => Object.hash(role, content, reasoningContent, functionCalls);
  
  bool _functionCallsEqual(List<LeapFunctionCall>? a, List<LeapFunctionCall>? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Represents different types of generation finish reasons.
enum GenerationFinishReason {
  /// Generation completed normally
  stop,
  /// Hit maximum token limit
  length,
  /// Generation was cancelled
  cancelled,
  /// Error occurred during generation
  error,
  /// Function call was triggered
  functionCall
}

/// Statistics about a completed generation.
class GenerationStats {
  /// Number of prompt tokens processed
  final int? promptTokens;
  
  /// Number of completion tokens generated
  final int? completionTokens;
  
  /// Total processing time in milliseconds
  final int? timeMs;
  
  /// Tokens per second generation rate
  final double? tokensPerSecond;

  const GenerationStats({
    this.promptTokens,
    this.completionTokens,
    this.timeMs,
    this.tokensPerSecond,
  });

  Map<String, dynamic> toMap() {
    return {
      'promptTokens': promptTokens,
      'completionTokens': completionTokens,
      'timeMs': timeMs,
      'tokensPerSecond': tokensPerSecond,
    };
  }

  factory GenerationStats.fromMap(Map<String, dynamic> map) {
    return GenerationStats(
      promptTokens: map['promptTokens']?.toInt(),
      completionTokens: map['completionTokens']?.toInt(),
      timeMs: map['timeMs']?.toInt(),
      tokensPerSecond: map['tokensPerSecond']?.toDouble(),
    );
  }

  @override
  String toString() {
    return 'GenerationStats(promptTokens: $promptTokens, completionTokens: $completionTokens, timeMs: $timeMs, tokensPerSecond: $tokensPerSecond)';
  }
}

/// Sealed class representing different types of message responses during generation.
/// 
/// This mirrors the MessageResponse from the native LEAP SDKs, providing structured
/// access to different response types during streaming generation.
abstract class MessageResponse {
  const MessageResponse();
}

/// Represents a chunk of generated text.
class MessageResponseChunk extends MessageResponse {
  /// The text content of this chunk
  final String text;
  
  const MessageResponseChunk(this.text);
  
  @override
  String toString() => 'MessageResponseChunk(text: "$text")';
  
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MessageResponseChunk && other.text == text);
  }
  
  @override
  int get hashCode => text.hashCode;
}

/// Represents a chunk of reasoning content.
class MessageResponseReasoningChunk extends MessageResponse {
  /// The reasoning text content of this chunk
  final String reasoning;
  
  const MessageResponseReasoningChunk(this.reasoning);
  
  @override
  String toString() => 'MessageResponseReasoningChunk(reasoning: "$reasoning")';
  
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MessageResponseReasoningChunk && other.reasoning == reasoning);
  }
  
  @override
  int get hashCode => reasoning.hashCode;
}

/// Represents function calls in a message response.
class MessageResponseFunctionCalls extends MessageResponse {
  /// List of function calls to be executed
  final List<LeapFunctionCall> functionCalls;
  
  const MessageResponseFunctionCalls(this.functionCalls);
  
  @override
  String toString() => 'MessageResponseFunctionCalls(functionCalls: $functionCalls)';
  
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MessageResponseFunctionCalls && 
         other.functionCalls.length == functionCalls.length &&
         other.functionCalls.every((call) => functionCalls.contains(call)));
  }
  
  @override
  int get hashCode => Object.hashAll(functionCalls);
}

/// Represents the completion of message generation.
class MessageResponseComplete extends MessageResponse {
  /// The complete generated message
  final ChatMessage message;
  
  /// Why the generation finished
  final GenerationFinishReason finishReason;
  
  /// Optional generation statistics
  final GenerationStats? stats;
  
  const MessageResponseComplete({
    required this.message,
    required this.finishReason,
    this.stats,
  });
  
  @override
  String toString() => 'MessageResponseComplete(message: $message, finishReason: $finishReason, stats: $stats)';
  
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is MessageResponseComplete && 
         other.message == message && 
         other.finishReason == finishReason &&
         other.stats == stats);
  }
  
  @override
  int get hashCode => Object.hash(message, finishReason, stats);
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

/// Represents a function call parameter.
class LeapFunctionParameter {
  /// Parameter name
  final String name;
  
  /// Parameter type (string, number, boolean, object, array)
  final String type;
  
  /// Parameter description
  final String description;
  
  /// Whether parameter is required
  final bool required;
  
  /// Enum values for string parameters
  final List<String>? enumValues;
  
  /// Properties for object parameters
  final Map<String, LeapFunctionParameter>? properties;
  
  /// Items schema for array parameters
  final LeapFunctionParameter? items;

  const LeapFunctionParameter({
    required this.name,
    required this.type,
    required this.description,
    this.required = false,
    this.enumValues,
    this.properties,
    this.items,
  });

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'name': name,
      'type': type,
      'description': description,
      'required': required,
    };
    
    if (enumValues != null) map['enum'] = enumValues;
    if (properties != null) {
      map['properties'] = properties!.map((k, v) => MapEntry(k, v.toMap()));
    }
    if (items != null) map['items'] = items!.toMap();
    
    return map;
  }

  factory LeapFunctionParameter.fromMap(Map<String, dynamic> map) {
    return LeapFunctionParameter(
      name: map['name'] ?? '',
      type: map['type'] ?? '',
      description: map['description'] ?? '',
      required: map['required'] ?? false,
      enumValues: map['enum']?.cast<String>(),
      properties: map['properties'] != null
          ? (map['properties'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, LeapFunctionParameter.fromMap(v)))
          : null,
      items: map['items'] != null 
          ? LeapFunctionParameter.fromMap(map['items'])
          : null,
    );
  }

  @override
  String toString() {
    return 'LeapFunctionParameter(name: $name, type: $type, required: $required)';
  }
}

/// Represents a callable function definition.
class LeapFunction {
  /// Function name
  final String name;
  
  /// Function description
  final String description;
  
  /// Function parameters
  final List<LeapFunctionParameter> parameters;
  
  /// Function implementation callback
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> arguments) implementation;

  const LeapFunction({
    required this.name,
    required this.description,
    required this.parameters,
    required this.implementation,
  });

  /// Get JSON schema for this function
  Map<String, dynamic> getSchema() {
    return {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': {
          for (final param in parameters)
            param.name: {
              'type': param.type,
              'description': param.description,
              if (param.enumValues != null) 'enum': param.enumValues,
              if (param.properties != null) 
                'properties': param.properties!.map((k, v) => MapEntry(k, v.toMap())),
              if (param.items != null) 'items': param.items!.toMap(),
            }
        },
        'required': parameters.where((p) => p.required).map((p) => p.name).toList(),
      },
    };
  }

  @override
  String toString() {
    return 'LeapFunction(name: $name, parameters: ${parameters.length})';
  }
}

/// Represents a function call made by the model.
class LeapFunctionCall {
  /// Function name to call
  final String name;
  
  /// Arguments to pass to the function
  final Map<String, dynamic> arguments;
  
  /// Unique ID for this function call
  final String? id;

  const LeapFunctionCall({
    required this.name,
    required this.arguments,
    this.id,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'arguments': arguments,
      if (id != null) 'id': id,
    };
  }

  factory LeapFunctionCall.fromMap(Map<String, dynamic> map) {
    return LeapFunctionCall(
      name: map['name'] ?? '',
      arguments: Map<String, dynamic>.from(map['arguments'] ?? {}),
      id: map['id'],
    );
  }

  String toJson() => json.encode(toMap());

  factory LeapFunctionCall.fromJson(String jsonString) => 
      LeapFunctionCall.fromMap(json.decode(jsonString));

  @override
  String toString() {
    return 'LeapFunctionCall(name: $name, arguments: $arguments${id != null ? ', id: $id' : ''})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LeapFunctionCall &&
        other.name == name &&
        other.id == id &&
        _mapsEqual(other.arguments, arguments);
  }

  @override
  int get hashCode => Object.hash(name, arguments, id);
  
  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }
}

/// Configuration options for model loading.
/// 
/// Controls various parameters that affect how models are loaded and initialized,
/// corresponding to ModelLoadingOptions in the native LEAP SDKs.
class ModelLoadingOptions {
  /// Whether to enable verbose logging during model loading
  final bool? verboseLogging;
  
  /// Maximum memory usage in MB (null = no limit)
  final int? maxMemoryMB;
  
  /// Number of threads to use for loading (null = auto)
  final int? numThreads;
  
  /// Whether to use GPU acceleration if available
  final bool? useGpu;
  
  /// GPU device ID to use (null = auto select)
  final int? gpuDeviceId;
  
  /// Additional configuration parameters
  final Map<String, dynamic>? additionalConfig;

  const ModelLoadingOptions({
    this.verboseLogging,
    this.maxMemoryMB,
    this.numThreads,
    this.useGpu,
    this.gpuDeviceId,
    this.additionalConfig,
  });

  /// Create with default settings optimized for performance
  factory ModelLoadingOptions.performance() {
    return const ModelLoadingOptions(
      verboseLogging: false,
      useGpu: true,
      numThreads: null, // Auto-detect optimal threads
    );
  }

  /// Create with default settings optimized for memory efficiency
  factory ModelLoadingOptions.memoryEfficient() {
    return const ModelLoadingOptions(
      verboseLogging: false,
      useGpu: false,
      numThreads: 2, // Use fewer threads
    );
  }

  /// Create with verbose logging enabled for debugging
  factory ModelLoadingOptions.debug() {
    return const ModelLoadingOptions(
      verboseLogging: true,
      useGpu: false,
      numThreads: 1,
    );
  }

  /// Convert to map for native method calls
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    
    if (verboseLogging != null) map['verboseLogging'] = verboseLogging;
    if (maxMemoryMB != null) map['maxMemoryMB'] = maxMemoryMB;
    if (numThreads != null) map['numThreads'] = numThreads;
    if (useGpu != null) map['useGpu'] = useGpu;
    if (gpuDeviceId != null) map['gpuDeviceId'] = gpuDeviceId;
    if (additionalConfig != null) map['additionalConfig'] = additionalConfig;
    
    return map;
  }

  /// Create from map
  factory ModelLoadingOptions.fromMap(Map<String, dynamic> map) {
    return ModelLoadingOptions(
      verboseLogging: map['verboseLogging'],
      maxMemoryMB: map['maxMemoryMB'],
      numThreads: map['numThreads'],
      useGpu: map['useGpu'],
      gpuDeviceId: map['gpuDeviceId'],
      additionalConfig: map['additionalConfig'],
    );
  }

  @override
  String toString() {
    final parts = <String>[];
    if (verboseLogging != null) parts.add('verboseLogging: $verboseLogging');
    if (maxMemoryMB != null) parts.add('maxMemoryMB: $maxMemoryMB');
    if (numThreads != null) parts.add('numThreads: $numThreads');
    if (useGpu != null) parts.add('useGpu: $useGpu');
    if (gpuDeviceId != null) parts.add('gpuDeviceId: $gpuDeviceId');
    if (additionalConfig != null) parts.add('additionalConfig: ${additionalConfig.toString()}');
    
    return 'ModelLoadingOptions(${parts.join(', ')})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ModelLoadingOptions &&
        other.verboseLogging == verboseLogging &&
        other.maxMemoryMB == maxMemoryMB &&
        other.numThreads == numThreads &&
        other.useGpu == useGpu &&
        other.gpuDeviceId == gpuDeviceId &&
        _mapsEqual(other.additionalConfig ?? {}, additionalConfig ?? {});
  }

  @override
  int get hashCode => Object.hash(
        verboseLogging,
        maxMemoryMB,
        numThreads,
        useGpu,
        gpuDeviceId,
        additionalConfig,
      );
      
  bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) return false;
    }
    return true;
  }
}

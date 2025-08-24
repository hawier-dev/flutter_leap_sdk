import 'dart:convert';
import 'flutter_leap_sdk_service.dart';
import 'models.dart';
import 'exceptions.dart';
import 'leap_logger.dart';

/// Represents a conversation session with persistent history and context.
///
/// This class manages a stateful conversation with the LEAP model, maintaining
/// message history and providing methods for generating responses within context.
/// It mirrors the Conversation API from the native LEAP SDKs.
class Conversation {
  /// Unique identifier for this conversation session
  final String id;
  
  /// List of messages in this conversation
  final List<ChatMessage> _history = [];
  
  /// Optional system prompt that sets the context for this conversation
  String? _systemPrompt;
  
  /// Whether this conversation is currently generating a response
  bool _isGenerating = false;
  
  /// Generation options to use for this conversation
  GenerationOptions? _generationOptions;
  
  /// Registered functions available for calling
  final Map<String, LeapFunction> _functions = {};

  /// Create a new conversation with optional system prompt
  Conversation({
    required this.id,
    String? systemPrompt,
    GenerationOptions? generationOptions,
  }) : _systemPrompt = systemPrompt,
       _generationOptions = generationOptions {
    
    // Add system message if provided
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      _history.add(ChatMessage.system(systemPrompt));
    }
    
    LeapLogger.info('Created conversation: $id');
  }


  /// Get read-only view of conversation history
  List<ChatMessage> get history => List.unmodifiable(_history);
  
  /// Get the system prompt for this conversation
  String? get systemPrompt => _systemPrompt;
  
  /// Whether the conversation is currently generating a response
  bool get isGenerating => _isGenerating;
  
  /// Current generation options
  GenerationOptions? get generationOptions => _generationOptions;
  
  /// Number of messages in the conversation
  int get messageCount => _history.length;
  
  /// Check if conversation has any user/assistant messages (excluding system)
  bool get hasMessages => _history.any((m) => m.role != MessageRole.system);

  /// Update the system prompt for this conversation
  /// 
  /// Note: This will clear the conversation history as the context changes
  void updateSystemPrompt(String? systemPrompt) {
    if (_systemPrompt == systemPrompt) return;
    
    _systemPrompt = systemPrompt;
    _history.clear();
    
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      _history.add(ChatMessage.system(systemPrompt));
    }
    
    LeapLogger.info('Updated system prompt for conversation: $id');
  }

  /// Update generation options for this conversation
  void updateGenerationOptions(GenerationOptions? options) {
    _generationOptions = options;
    LeapLogger.info('Updated generation options for conversation: $id');
  }

  /// Add a message to the conversation history
  void addMessage(ChatMessage message) {
    _history.add(message);
    LeapLogger.info('Added ${message.role.name} message to conversation: $id');
  }

  /// Register a function for the model to call
  Future<void> registerFunction(LeapFunction function) async {
    _functions[function.name] = function;
    
    // Register with native SDK
    try {
      await FlutterLeapSdkService.registerFunction(
        conversationId: id,
        functionName: function.name,
        functionSchema: function.getSchema(),
      );
      LeapLogger.info('Registered function "${function.name}" for conversation: $id');
    } catch (e) {
      _functions.remove(function.name);
      LeapLogger.error('Failed to register function "${function.name}"', e);
      rethrow;
    }
  }

  /// Unregister a function
  Future<void> unregisterFunction(String functionName) async {
    try {
      await FlutterLeapSdkService.unregisterFunction(
        conversationId: id,
        functionName: functionName,
      );
      _functions.remove(functionName);
      LeapLogger.info('Unregistered function "$functionName" from conversation: $id');
    } catch (e) {
      LeapLogger.error('Failed to unregister function "$functionName"', e);
      rethrow;
    }
  }

  /// Get all registered functions
  List<LeapFunction> get registeredFunctions => _functions.values.toList();

  /// Check if a function is registered
  bool hasFunction(String functionName) => _functions.containsKey(functionName);

  /// Execute a function call
  Future<Map<String, dynamic>> executeFunction(LeapFunctionCall functionCall) async {
    final function = _functions[functionCall.name];
    if (function == null) {
      throw GenerationException('Function "${functionCall.name}" is not registered', 'FUNCTION_NOT_FOUND');
    }

    try {
      LeapLogger.info('Executing function "${functionCall.name}" with ${functionCall.arguments.length} arguments');
      final result = await function.implementation(functionCall.arguments);
      LeapLogger.info('Function "${functionCall.name}" executed successfully');
      return result;
    } catch (e) {
      LeapLogger.error('Function "${functionCall.name}" execution failed', e);
      rethrow;
    }
  }

  /// Generate a response to a user message
  /// 
  /// Adds the user message to history and generates an assistant response.
  /// Returns the assistant's response text.
  Future<String> generateResponse(String userMessage) async {
    if (_isGenerating) {
      throw GenerationException('Conversation is already generating a response', 'GENERATION_IN_PROGRESS');
    }

    if (userMessage.trim().isEmpty) {
      throw GenerationException('Message cannot be empty', 'INVALID_INPUT');
    }

    _isGenerating = true;
    
    try {
      // Add user message to history
      final userMsg = ChatMessage.user(userMessage);
      addMessage(userMsg);

      LeapLogger.info('Generating response for conversation: $id (${userMessage.length} chars)');

      // Generate response using the service
      final response = await FlutterLeapSdkService.generateConversationResponse(
        conversationId: id,
        message: userMessage,
        history: _history,
        generationOptions: _generationOptions,
      );

      // Add assistant response to history
      final assistantMsg = ChatMessage.assistant(response);
      addMessage(assistantMsg);

      LeapLogger.info('Generated response for conversation: $id (${response.length} chars)');
      
      return response;
      
    } finally {
      _isGenerating = false;
    }
  }

  /// Generate a streaming response to a user message
  /// 
  /// Adds the user message to history and generates a streaming assistant response.
  /// Yields response chunks as they are generated.
  Stream<String> generateResponseStream(String userMessage) async* {
    if (_isGenerating) {
      throw GenerationException('Conversation is already generating a response', 'GENERATION_IN_PROGRESS');
    }

    if (userMessage.trim().isEmpty) {
      throw GenerationException('Message cannot be empty', 'INVALID_INPUT');
    }

    _isGenerating = true;
    
    try {
      // Add user message to history
      final userMsg = ChatMessage.user(userMessage);
      addMessage(userMsg);

      LeapLogger.info('Starting streaming response for conversation: $id (${userMessage.length} chars)');

      String fullResponse = '';
      
      // Generate streaming response using the service
      await for (final chunk in FlutterLeapSdkService.generateConversationResponseStream(
        conversationId: id,
        message: userMessage,
        history: _history,
        generationOptions: _generationOptions,
      )) {
        fullResponse += chunk;
        yield chunk;
      }

      // Add complete assistant response to history
      if (fullResponse.isNotEmpty) {
        final assistantMsg = ChatMessage.assistant(fullResponse);
        addMessage(assistantMsg);
      }

      LeapLogger.info('Completed streaming response for conversation: $id (${fullResponse.length} chars)');
      
    } finally {
      _isGenerating = false;
    }
  }

  /// Clear all messages from the conversation (except system prompt)
  void clearHistory() {
    final systemMessage = _history.where((m) => m.role == MessageRole.system).firstOrNull;
    _history.clear();
    
    if (systemMessage != null) {
      _history.add(systemMessage);
    }
    
    LeapLogger.info('Cleared history for conversation: $id');
  }

  /// Remove the last message from the conversation
  /// 
  /// Returns the removed message, or null if history is empty or only contains system message
  ChatMessage? removeLastMessage() {
    // Don't remove system messages
    final nonSystemMessages = _history.where((m) => m.role != MessageRole.system).toList();
    if (nonSystemMessages.isEmpty) return null;
    
    final lastMessage = nonSystemMessages.last;
    _history.remove(lastMessage);
    
    LeapLogger.info('Removed last ${lastMessage.role.name} message from conversation: $id');
    return lastMessage;
  }

  /// Export conversation to JSON string (Flutter custom format)
  String toJson() {
    final data = {
      'id': id,
      'systemPrompt': _systemPrompt,
      'generationOptions': _generationOptions?.toMap(),
      'history': _history.map((m) => m.toMap()).toList(),
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    
    return json.encode(data);
  }

  /// Export conversation to JSONArray format (official LEAP SDK compatible)
  List<Map<String, dynamic>> exportToJSONArray() {
    return _history.map((message) => {
      'role': message.role.name,
      'content': message.content,
      if (message.reasoningContent != null) 'reasoningContent': message.reasoningContent,
      if (message.functionCalls != null && message.functionCalls!.isNotEmpty) 
        'functionCalls': message.functionCalls!.map((fc) => fc.toMap()).toList(),
    }).toList();
  }

  /// Create conversation from JSON string
  static Conversation fromJson(String jsonString) {
    final data = json.decode(jsonString);
    
    final conversation = Conversation(
      id: data['id'],
      systemPrompt: data['systemPrompt'],
      generationOptions: data['generationOptions'] != null 
          ? GenerationOptions.fromMap(data['generationOptions'])
          : null,
    );
    
    // Clear the auto-added system message and restore from JSON
    conversation._history.clear();
    
    // Restore history
    if (data['history'] != null) {
      for (final msgData in data['history']) {
        conversation._history.add(ChatMessage.fromMap(msgData));
      }
    }
    
    return conversation;
  }

  /// Create conversation from history array (official LEAP SDK compatible)
  static Conversation createConversationFromHistory({
    required String id,
    required List<Map<String, dynamic>> history,
    String? systemPrompt,
    GenerationOptions? generationOptions,
  }) {
    final conversation = Conversation(
      id: id,
      systemPrompt: systemPrompt,
      generationOptions: generationOptions,
    );
    
    // Clear auto-added system message
    conversation._history.clear();
    
    // Convert and add messages
    for (final messageData in history) {
      final role = MessageRole.values.firstWhere(
        (r) => r.name == messageData['role'],
        orElse: () => MessageRole.user,
      );
      
      final functionCalls = messageData['functionCalls'] != null
          ? (messageData['functionCalls'] as List)
              .map((fc) => LeapFunctionCall.fromMap(fc))
              .toList()
          : null;
      
      final message = ChatMessage(
        role: role,
        content: messageData['content'] ?? '',
        reasoningContent: messageData['reasoningContent'],
        functionCalls: functionCalls,
      );
      
      conversation._history.add(message);
    }
    
    LeapLogger.info('Created conversation from history: $id (${history.length} messages)');
    return conversation;
  }

  /// Export conversation to a map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'systemPrompt': _systemPrompt,
      'generationOptions': _generationOptions?.toMap(),
      'history': _history.map((m) => m.toMap()).toList(),
      'messageCount': messageCount,
      'hasMessages': hasMessages,
      'isGenerating': _isGenerating,
    };
  }

  /// Get conversation statistics
  Map<String, dynamic> getStats() {
    final messagesByRole = <String, int>{};
    for (final message in _history) {
      messagesByRole[message.role.name] = (messagesByRole[message.role.name] ?? 0) + 1;
    }
    
    return {
      'id': id,
      'messageCount': messageCount,
      'messagesByRole': messagesByRole,
      'hasSystemPrompt': _systemPrompt != null,
      'hasGenerationOptions': _generationOptions != null,
      'isGenerating': _isGenerating,
      'hasMessages': hasMessages,
    };
  }

  /// Cancel any ongoing generation
  Future<void> cancelGeneration() async {
    if (_isGenerating) {
      await FlutterLeapSdkService.cancelStreaming();
      _isGenerating = false;
      LeapLogger.info('Cancelled generation for conversation: $id');
    }
  }

  /// Generate a structured response with MessageResponse support
  /// 
  /// This method returns structured MessageResponse objects instead of plain strings,
  /// allowing access to chunks, reasoning, function calls, and completion info.
  Stream<MessageResponse> generateResponseStructured(String userMessage) async* {
    if (_isGenerating) {
      throw GenerationException('Conversation is already generating a response', 'GENERATION_IN_PROGRESS');
    }

    if (userMessage.trim().isEmpty) {
      throw GenerationException('Message cannot be empty', 'INVALID_INPUT');
    }

    _isGenerating = true;
    
    try {
      // Add user message to history
      final userMsg = ChatMessage.user(userMessage);
      addMessage(userMsg);

      LeapLogger.info('Generating structured response for conversation: $id (${userMessage.length} chars)');

      String fullResponse = '';
      String fullReasoning = '';
      List<LeapFunctionCall> functionCalls = [];
      
      // Generate streaming response using the service
      await for (final chunk in FlutterLeapSdkService.generateConversationResponseStream(
        conversationId: id,
        message: userMessage,
        history: _history,
        generationOptions: _generationOptions,
      )) {
        if (chunk == '<STREAM_END>') {
          // Create completion response
          final assistantMsg = ChatMessage.assistant(
            fullResponse, 
            reasoningContent: fullReasoning.isEmpty ? null : fullReasoning,
            functionCalls: functionCalls.isEmpty ? null : functionCalls,
          );
          
          addMessage(assistantMsg);
          
          yield MessageResponseComplete(
            message: assistantMsg,
            finishReason: functionCalls.isNotEmpty ? GenerationFinishReason.functionCall : GenerationFinishReason.stop,
            stats: null, // TODO: Add stats from native
          );
          break;
        } else {
          // For now, treat all chunks as regular text chunks
          // TODO: Parse and detect reasoning chunks and function calls from native
          fullResponse += chunk;
          yield MessageResponseChunk(chunk);
        }
      }

      LeapLogger.info('Completed structured response for conversation: $id (${fullResponse.length} chars)');
      
    } finally {
      _isGenerating = false;
    }
  }

  /// Execute function calls and continue generation if needed
  Future<void> executeFunctionCalls(List<LeapFunctionCall> functionCalls) async {
    final results = <Map<String, dynamic>>[];
    
    for (final functionCall in functionCalls) {
      try {
        final result = await executeFunction(functionCall);
        results.add({
          'call': functionCall.toMap(),
          'result': result,
          'success': true,
        });
      } catch (e) {
        results.add({
          'call': functionCall.toMap(),
          'error': e.toString(),
          'success': false,
        });
      }
    }
    
    // Add function results as a system message for context
    final resultsMessage = ChatMessage.system(
      'Function call results: ${json.encode(results)}'
    );
    addMessage(resultsMessage);
    
    LeapLogger.info('Executed ${functionCalls.length} function calls for conversation: $id');
  }

  @override
  String toString() {
    final parts = ['id: $id', 'messages: $messageCount', 'generating: $_isGenerating'];
    if (_functions.isNotEmpty) parts.add('functions: ${_functions.length}');
    return 'Conversation(${parts.join(', ')})';
  }
}
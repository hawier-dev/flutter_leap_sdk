import 'dart:convert';
import 'dart:typed_data';
import 'flutter_leap_sdk_service.dart';
import 'models.dart';
import 'exceptions.dart';

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
    
  }

  /// Update generation options for this conversation
  void updateGenerationOptions(GenerationOptions? options) {
    _generationOptions = options;
  }

  /// Add a message to the conversation history
  void addMessage(ChatMessage message) {
    _history.add(message);
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
    } catch (e) {
      _functions.remove(function.name);
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
    } catch (e) {
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
      final result = await function.implementation(functionCall.arguments);
      return result;
    } catch (e) {
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
    if (userMessage.trim().isEmpty) {
      throw GenerationException('Message cannot be empty', 'INVALID_INPUT');
    }

    if (_isGenerating) {
      throw GenerationException('Conversation is already generating a response', 'GENERATION_IN_PROGRESS');
    }

    _isGenerating = true;
    
    try {
      // Add user message to history
      final userMsg = ChatMessage.user(userMessage);
      addMessage(userMsg);


      String fullResponse = '';
      bool hasReceivedAnyResponse = false;
      
      // Generate streaming response using the service
      await for (final chunk in FlutterLeapSdkService.generateConversationResponseStream(
        conversationId: id,
        message: userMessage,
        history: _history,
        generationOptions: _generationOptions,
      )) {
        hasReceivedAnyResponse = true;
        fullResponse += chunk;
        yield chunk;
      }

      // Add complete assistant response to history or handle unexpected termination
      if (fullResponse.isNotEmpty) {
        final assistantMsg = ChatMessage.assistant(fullResponse);
        addMessage(assistantMsg);
      } else if (!hasReceivedAnyResponse) {
        // Stream ended without any response - likely stopped unexpectedly
        final assistantMsg = ChatMessage.assistant('[Generation stopped unexpectedly]');
        addMessage(assistantMsg);
      }

      
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
      try {
        await FlutterLeapSdkService.cancelStreaming();
      } catch (e) {
        // Ignore cancellation errors
      } finally {
        _isGenerating = false;  // Always reset flag
      }
    }
  }

  /// Generate a structured response with MessageResponse support
  /// 
  /// This method returns structured MessageResponse objects instead of plain strings,
  /// allowing access to chunks, reasoning, function calls, and completion info.
  Stream<MessageResponse> generateResponseStructured(String userMessage) async* {
    if (userMessage.trim().isEmpty) {
      throw GenerationException('Message cannot be empty', 'INVALID_INPUT');
    }

    if (_isGenerating) {
      throw GenerationException('Conversation is already generating a response', 'GENERATION_IN_PROGRESS');
    }

    _isGenerating = true;
    
    try {
      // Add user message to history
      final userMsg = ChatMessage.user(userMessage);
      addMessage(userMsg);


      String fullResponse = '';
      String fullReasoning = '';
      List<LeapFunctionCall> functionCalls = [];
      
      // Generate streaming response using the service
      bool hasReceivedAnyResponse = false;
      await for (final response in FlutterLeapSdkService.generateConversationResponseStructured(
        conversationId: id,
        message: userMessage,
        history: _history,
        generationOptions: _generationOptions,
      )) {
        hasReceivedAnyResponse = true;
        
        if (response is MessageResponseChunk) {
          fullResponse += response.text;
          yield response;
        } else if (response is MessageResponseReasoningChunk) {
          fullReasoning += response.reasoning;
          yield response;
        } else if (response is MessageResponseFunctionCalls) {
          functionCalls.addAll(response.functionCalls);
          yield response;
        } else if (response is MessageResponseComplete) {
          // Create completion response with accumulated data
          final assistantMsg = ChatMessage.assistant(
            fullResponse, 
            reasoningContent: fullReasoning.isEmpty ? null : fullReasoning,
            functionCalls: functionCalls.isEmpty ? null : functionCalls,
          );
          
          addMessage(assistantMsg);
          
          yield MessageResponseComplete(
            message: assistantMsg,
            finishReason: functionCalls.isNotEmpty ? GenerationFinishReason.functionCall : response.finishReason,
            stats: response.stats,
          );
          break;
        }
      }
      
      // If stream ended without completion response and we have some content, create completion
      if (!hasReceivedAnyResponse || (fullResponse.isNotEmpty && !_history.any((m) => m.content == fullResponse))) {
        
        if (fullResponse.isNotEmpty || functionCalls.isNotEmpty) {
          final assistantMsg = ChatMessage.assistant(
            fullResponse.isEmpty ? '[Generation stopped unexpectedly]' : fullResponse,
            reasoningContent: fullReasoning.isEmpty ? null : fullReasoning,
            functionCalls: functionCalls.isEmpty ? null : functionCalls,
          );
          
          addMessage(assistantMsg);
          
          yield MessageResponseComplete(
            message: assistantMsg,
            finishReason: GenerationFinishReason.stop,
            stats: null,
          );
        }
      }

      
    } catch (e) {
      rethrow;
    } finally {
      _isGenerating = false;
    }
  }

  /// Add function call results to conversation history
  /// 
  /// This method should be called by the application after executing function calls.
  /// The results will be added as a system message to provide context for further generation.
  void addFunctionResults(List<Map<String, dynamic>> results) {
    final resultsMessage = ChatMessage.system(
      'Function call results: ${json.encode(results)}'
    );
    addMessage(resultsMessage);
    
  }

  /// Generate a response with an image (for vision models)
  /// 
  /// Adds the user message and image to history and generates an assistant response.
  /// This method requires a vision-capable model to be loaded.
  Future<String> generateResponseWithImage(String userMessage, Uint8List imageBytes) async {
    if (_isGenerating) {
      throw GenerationException('Conversation is already generating a response', 'GENERATION_IN_PROGRESS');
    }

    if (userMessage.trim().isEmpty) {
      throw GenerationException('Message cannot be empty', 'INVALID_INPUT');
    }

    if (imageBytes.isEmpty) {
      throw GenerationException('Image data cannot be empty', 'INVALID_INPUT');
    }

    _isGenerating = true;
    
    try {
      // Add user message with image to history
      final userMsg = ChatMessage.user(userMessage);
      addMessage(userMsg);

      // Use the conversation-aware method that maintains conversation state
      final response = await FlutterLeapSdkService.generateConversationResponseWithImage(
        conversationId: id,
        message: userMessage,
        imageBytes: imageBytes,
      );

      // Add assistant response to history
      final assistantMsg = ChatMessage.assistant(response);
      addMessage(assistantMsg);

      return response;
      
    } finally {
      _isGenerating = false;
    }
  }


  @override
  String toString() {
    final parts = ['id: $id', 'messages: $messageCount', 'generating: $_isGenerating'];
    if (_functions.isNotEmpty) parts.add('functions: ${_functions.length}');
    return 'Conversation(${parts.join(', ')})';
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_leap_sdk/flutter_leap_sdk.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LEAP SDK Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const DemoTabbedScreen(),
    );
  }
}

class DemoTabbedScreen extends StatefulWidget {
  const DemoTabbedScreen({super.key});

  @override
  State<DemoTabbedScreen> createState() => _DemoTabbedScreenState();
}

class _DemoTabbedScreenState extends State<DemoTabbedScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isModelLoaded = false;
  String _status = 'Checking model status...';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    FlutterLeapSdkService.initialize();
    _checkModelStatus();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkModelStatus() async {
    try {
      final isLoaded = await FlutterLeapSdkService.checkModelLoaded();
      final downloadedModels = await FlutterLeapSdkService.getDownloadedModels();

      setState(() {
        _isModelLoaded = isLoaded;
        
        if (isLoaded) {
          _status = '✅ Model ready: ${FlutterLeapSdkService.currentModel}';
        } else if (downloadedModels.isNotEmpty) {
          _status = '📁 ${downloadedModels.length} model(s) available - Load to start';
        } else {
          _status = '⬇️ No models found - Download to start';
        }
      });
    } catch (e) {
      setState(() {
        _status = '❌ Error: ${e.toString().split('\n').first}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LEAP SDK Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.chat), text: 'Chat'),
            Tab(icon: Icon(Icons.functions), text: 'Functions'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isModelLoaded ? Colors.green.shade50 : Colors.orange.shade50,
            child: Row(
              children: [
                Icon(
                  _isModelLoaded ? Icons.check_circle : Icons.warning,
                  color: _isModelLoaded ? Colors.green : Colors.orange,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _status,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (!_isModelLoaded)
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _checkModelStatus,
                    tooltip: 'Refresh status',
                  ),
              ],
            ),
          ),
          
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ChatTab(isModelLoaded: _isModelLoaded, onModelStatusChanged: _checkModelStatus),
                FunctionCallingTab(isModelLoaded: _isModelLoaded),
                SettingsTab(onModelStatusChanged: _checkModelStatus),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Chat Tab - Basic conversation functionality
class ChatTab extends StatefulWidget {
  final bool isModelLoaded;
  final VoidCallback onModelStatusChanged;

  const ChatTab({
    super.key,
    required this.isModelLoaded,
    required this.onModelStatusChanged,
  });

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  Conversation? _conversation;
  List<ChatMessage> _messages = [];
  bool _isTyping = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _createConversation() async {
    if (!widget.isModelLoaded) return;
    
    try {
      final conversation = await FlutterLeapSdkService.createConversation(
        systemPrompt: "You are a helpful AI assistant. Be concise and friendly.",
        generationOptions: GenerationOptions.balanced(),
      );
      
      setState(() {
        _conversation = conversation;
        _messages = [];
      });
    } catch (e) {
      _showErrorDialog('Failed to create conversation: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _conversation == null) return;
    
    final userMessage = _messageController.text.trim();
    _messageController.clear();
    
    setState(() {
      _messages.add(ChatMessage.user(userMessage));
      _isTyping = true;
    });
    
    _scrollToBottom();
    
    try {
      String assistantResponse = '';
      
      await for (final chunk in _conversation!.generateResponseStream(userMessage)) {
        setState(() {
          if (_messages.isEmpty || _messages.last.role != MessageRole.assistant) {
            _messages.add(ChatMessage.assistant(''));
          }
          assistantResponse += chunk;
          _messages[_messages.length - 1] = ChatMessage.assistant(assistantResponse);
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage.assistant('Error: ${e.toString()}'));
      });
    } finally {
      setState(() {
        _isTyping = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isModelLoaded) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber, size: 64, color: Colors.orange),
            SizedBox(height: 16),
            Text(
              'Model not loaded',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Please load a model in the Settings tab to start chatting',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Messages
        Expanded(
          child: _conversation == null 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'Ready to chat!\nTap "Start New Chat" to begin.',
                      style: TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return _buildTypingIndicator();
                  }
                  
                  final message = _messages[index];
                  return _buildMessageBubble(message);
                },
              ),
        ),
        
        // Input
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == MessageRole.user;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.purple.shade100,
              child: Icon(Icons.android, size: 16, color: Colors.purple.shade700),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue.shade500 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.person, size: 16, color: Colors.blue.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.purple.shade100,
            child: Icon(Icons.android, size: 16, color: Colors.purple.shade700),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(3, (index) => 
                  Container(
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_conversation == null)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _createConversation,
                icon: const Icon(Icons.chat),
                label: const Text('Start New Chat'),
              ),
            )
          else ...[
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
                enabled: !_isTyping,
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: _isTyping ? null : _sendMessage,
              mini: true,
              child: Icon(_isTyping ? Icons.hourglass_empty : Icons.send),
            ),
          ],
        ],
      ),
    );
  }
}

// Function Calling Tab - Demonstrates function registration and calling
class FunctionCallingTab extends StatefulWidget {
  final bool isModelLoaded;

  const FunctionCallingTab({
    super.key,
    required this.isModelLoaded,
  });

  @override
  State<FunctionCallingTab> createState() => _FunctionCallingTabState();
}

class _FunctionCallingTabState extends State<FunctionCallingTab> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  Conversation? _conversation;
  List<ChatMessage> _messages = [];
  bool _isTyping = false;
  List<String> _registeredFunctions = [];

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _createConversationWithFunctions() async {
    if (!widget.isModelLoaded) return;
    
    try {
      final conversation = await FlutterLeapSdkService.createConversation(
        systemPrompt: "You are a helpful assistant with access to various functions. Use them when appropriate to help the user.",
        generationOptions: GenerationOptions.balanced(),
      );
      
      // Register sample functions
      await _registerSampleFunctions(conversation);
      
      setState(() {
        _conversation = conversation;
        _messages = [];
      });
    } catch (e) {
      _showErrorDialog('Failed to create conversation: $e');
    }
  }

  Future<void> _registerSampleFunctions(Conversation conversation) async {
    final functions = [
      // Weather function
      LeapFunction(
        name: 'get_weather',
        description: 'Get current weather information for a location',
        parameters: [
          LeapFunctionParameter(
            name: 'location',
            type: 'string',
            description: 'The city or location to get weather for',
            required: true,
          ),
          LeapFunctionParameter(
            name: 'unit',
            type: 'string',
            description: 'Temperature unit (celsius or fahrenheit)',
            enumValues: ['celsius', 'fahrenheit'],
          ),
        ],
        implementation: (args) async {
          final location = args['location'] as String;
          final unit = args['unit'] as String? ?? 'celsius';
          // Mock weather response
          return {
            'location': location,
            'temperature': unit == 'celsius' ? 22 : 72,
            'unit': unit,
            'description': 'Partly cloudy',
            'humidity': 65,
          };
        },
      ),
      
      // Time function
      LeapFunction(
        name: 'get_current_time',
        description: 'Get the current date and time',
        parameters: [
          LeapFunctionParameter(
            name: 'timezone',
            type: 'string',
            description: 'Timezone (optional, defaults to local)',
          ),
        ],
        implementation: (args) async {
          final now = DateTime.now();
          return {
            'datetime': now.toIso8601String(),
            'formatted': '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
            'timezone': args['timezone'] ?? 'Local',
          };
        },
      ),
      
      // Calculator function
      LeapFunction(
        name: 'calculate_math_expression',
        description: 'Perform basic mathematical calculations',
        parameters: [
          LeapFunctionParameter(
            name: 'expression',
            type: 'string',
            description: 'Mathematical expression to evaluate (e.g., "2 + 3 * 4")',
            required: true,
          ),
        ],
        implementation: (args) async {
          final expression = args['expression'] as String;
          // Simple calculator implementation
          try {
            // This is a mock - in real implementation you'd use a proper expression parser
            final result = _evaluateExpression(expression);
            return {
              'expression': expression,
              'result': result,
              'success': true,
            };
          } catch (e) {
            return {
              'expression': expression,
              'error': 'Invalid expression',
              'success': false,
            };
          }
        },
      ),
    ];

    List<String> registered = [];
    for (final function in functions) {
      try {
        await conversation.registerFunction(function);
        registered.add(function.name);
      } catch (e) {
        debugPrint('Failed to register function ${function.name}: $e');
      }
    }
    
    setState(() {
      _registeredFunctions = registered;
    });
  }

  double _evaluateExpression(String expression) {
    // Mock calculator - replace with proper expression parser
    expression = expression.replaceAll(' ', '');
    if (expression.contains('+')) {
      final parts = expression.split('+');
      return double.parse(parts[0]) + double.parse(parts[1]);
    } else if (expression.contains('-')) {
      final parts = expression.split('-');
      return double.parse(parts[0]) - double.parse(parts[1]);
    } else if (expression.contains('*')) {
      final parts = expression.split('*');
      return double.parse(parts[0]) * double.parse(parts[1]);
    } else if (expression.contains('/')) {
      final parts = expression.split('/');
      return double.parse(parts[0]) / double.parse(parts[1]);
    }
    return double.parse(expression);
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _conversation == null) return;
    
    final userMessage = _messageController.text.trim();
    _messageController.clear();
    
    setState(() {
      _messages.add(ChatMessage.user(userMessage));
      _isTyping = true;
    });
    
    _scrollToBottom();
    
    String assistantResponse = '';
    
    try {
      
      // Use structured streaming to handle function calls
      await for (final response in _conversation!.generateResponseStructured(userMessage)) {
        if (response is MessageResponseChunk) {
          assistantResponse += response.text;
          setState(() {
            if (_messages.isEmpty || _messages.last.role != MessageRole.assistant) {
              _messages.add(ChatMessage.assistant(''));
            }
            _messages[_messages.length - 1] = ChatMessage.assistant(assistantResponse);
          });
          _scrollToBottom();
        } else if (response is MessageResponseFunctionCalls) {
          // Show function call indicators in UI
          setState(() {
            if (_messages.isEmpty || _messages.last.role != MessageRole.assistant) {
              _messages.add(ChatMessage.assistant(''));
            }
            String functionDisplay = assistantResponse;
            functionDisplay += '\n\n🔧 Calling functions:\n';
            for (final call in response.functionCalls) {
              functionDisplay += '• ${call.name}(${call.arguments.entries.map((e) => '${e.key}: ${e.value}').join(', ')})\n';
            }
            _messages[_messages.length - 1] = ChatMessage.assistant(functionDisplay);
          });
          _scrollToBottom();
        } else if (response is MessageResponseComplete) {
          // Handle function calling completion properly
          if (response.finishReason == GenerationFinishReason.functionCall && 
              response.message.functionCalls != null && 
              response.message.functionCalls!.isNotEmpty) {
            
            // Execute functions in the application (not in library)
            final results = await _executeFunctionCalls(response.message.functionCalls!);
            
            // Add results to conversation using the new API
            _conversation!.addFunctionResults(results);
            
            // Show function results to user
            setState(() {
              String finalDisplay = assistantResponse;
              finalDisplay += '\n\n✅ Functions executed:\n';
              
              for (final result in results) {
                final call = result['call'] as Map<String, dynamic>;
                final functionName = call['name'] as String;
                final success = result['success'] as bool;
                
                if (success) {
                  final functionResult = result['result'] as Map<String, dynamic>;
                  
                  if (functionName == 'calculate_math_expression' && functionResult['success'] == true) {
                    final expression = functionResult['expression'];
                    final calculationResult = functionResult['result'];
                    finalDisplay += '🧮 $expression = $calculationResult\n';
                  } else if (functionName == 'get_weather') {
                    final location = functionResult['location'];
                    final temp = functionResult['temperature'];
                    final unit = functionResult['unit'];
                    final description = functionResult['description'];
                    finalDisplay += '🌤️ Weather in $location: $temp°${unit == 'celsius' ? 'C' : 'F'}, $description\n';
                  } else if (functionName == 'get_current_time') {
                    final formatted = functionResult['formatted'];
                    finalDisplay += '🕒 Current time: $formatted\n';
                  }
                } else {
                  final error = result['error'] as String;
                  finalDisplay += '❌ Error executing $functionName: $error\n';
                }
              }
              
              finalDisplay += '\n💬 Ask follow-up questions to get AI response about these results!';
              _messages[_messages.length - 1] = ChatMessage.assistant(finalDisplay);
            });
            _scrollToBottom();
          }
          break;
        }
      }
    } catch (e) {
      setState(() {
        String errorMsg = 'Error: ${e.toString()}';
        
        // Detect common generation issues
        if (e.toString().toLowerCase().contains('generation') && 
            e.toString().toLowerCase().contains('progress')) {
          errorMsg = '⚠️ Generation was interrupted. This might happen due to rapid consecutive requests. Please try again.';
        } else if (e.toString().toLowerCase().contains('stop')) {
          errorMsg = '⚠️ Generation was stopped. This can happen during system optimization. Please try again.';
        }
        
        _messages.add(ChatMessage.assistant(errorMsg));
      });
    } finally {
      setState(() {
        _isTyping = false;
      });
    }
    _scrollToBottom();
  }

  /// Execute function calls in the application
  /// This is where the application implements the actual function logic
  Future<List<Map<String, dynamic>>> _executeFunctionCalls(List<LeapFunctionCall> functionCalls) async {
    final results = <Map<String, dynamic>>[];
    
    for (final functionCall in functionCalls) {
      try {
        Map<String, dynamic> result;
        
        switch (functionCall.name) {
          case 'get_weather':
            final location = functionCall.arguments['location'] as String;
            final unit = functionCall.arguments['unit'] as String? ?? 'celsius';
            result = {
              'location': location,
              'temperature': unit == 'celsius' ? 22 : 72,
              'unit': unit,
              'description': 'Partly cloudy',
              'humidity': 65,
            };
            break;
            
          case 'get_current_time':
            final now = DateTime.now();
            result = {
              'datetime': now.toIso8601String(),
              'formatted': '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
              'timezone': functionCall.arguments['timezone'] ?? 'Local',
            };
            break;
            
          case 'calculate_math_expression':
            final expression = functionCall.arguments['expression'] as String;
            try {
              final calculationResult = _evaluateExpression(expression);
              result = {
                'expression': expression,
                'result': calculationResult,
                'success': true,
              };
            } catch (e) {
              result = {
                'expression': expression,
                'error': 'Invalid expression',
                'success': false,
              };
            }
            break;
            
          default:
            throw Exception('Unknown function: ${functionCall.name}');
        }
        
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
    
    return results;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isModelLoaded) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber, size: 64, color: Colors.orange),
            SizedBox(height: 16),
            Text(
              'Model not loaded',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              'Please load a model in the Settings tab to use functions',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Function info
        if (_registeredFunctions.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Registered Functions:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: _registeredFunctions.map((name) => Chip(
                    label: Text(name),
                    backgroundColor: Colors.blue.shade100,
                    labelStyle: const TextStyle(fontSize: 12),
                  )).toList(),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Try asking: "What\'s the weather in London?", "What time is it?", or "Calculate 15 + 27"',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
        
        // Messages
        Expanded(
          child: _conversation == null 
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.functions, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'Function Calling Demo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This demonstrates how the AI can call functions\nto get real-time information and perform tasks.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length && _isTyping) {
                    return _buildTypingIndicator();
                  }
                  
                  final message = _messages[index];
                  return _buildMessageBubble(message);
                },
              ),
        ),
        
        // Input
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == MessageRole.user;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.purple.shade100,
              child: Icon(Icons.functions, size: 16, color: Colors.purple.shade700),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue.shade500 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          
          if (isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue.shade100,
              child: Icon(Icons.person, size: 16, color: Colors.blue.shade700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.purple.shade100,
            child: Icon(Icons.functions, size: 16, color: Colors.purple.shade700),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...List.generate(3, (index) => 
                  Container(
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_conversation == null)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _createConversationWithFunctions,
                icon: const Icon(Icons.functions),
                label: const Text('Start Function Demo'),
              ),
            )
          else ...[
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Ask about weather, time, or calculations...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
                enabled: !_isTyping,
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: _isTyping ? null : _sendMessage,
              mini: true,
              child: Icon(_isTyping ? Icons.hourglass_empty : Icons.send),
            ),
          ],
        ],
      ),
    );
  }
}


// Settings Tab - Model management and configuration
class SettingsTab extends StatefulWidget {
  final VoidCallback onModelStatusChanged;

  const SettingsTab({
    super.key,
    required this.onModelStatusChanged,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  String? _currentDownloadTaskId;
  double _downloadProgress = 0.0;
  String _downloadSpeed = '';
  List<String> _downloadedModels = [];
  bool _isLoading = true;
  String? _selectedModel;
  
  // Available models to download
  static const Map<String, String> availableModels = {
    'LFM2-350M': 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
    'LFM2-1.2B': 'LFM2-1.2B-8da4w_output_8da8w-seq_4096.bundle',
  };

  @override
  void initState() {
    super.initState();
    _selectedModel = availableModels.keys.first; // Default to first model
    _loadModelInfo();
  }

  Future<void> _loadModelInfo() async {
    try {
      final models = await FlutterLeapSdkService.getDownloadedModels();
      setState(() {
        _downloadedModels = models;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _downloadModel() async {
    if (_selectedModel == null) return;
    
    try {
      setState(() {
        _downloadProgress = 0.0;
        _downloadSpeed = '';
      });

      final modelBundle = availableModels[_selectedModel]!;
      final taskId = await FlutterLeapSdkService.downloadModel(
        modelName: modelBundle,
        onProgress: (progress) {
          setState(() {
            _downloadProgress = progress.percentage;
            _downloadSpeed = progress.speed;
            
            if (progress.percentage >= 100.0) {
              _currentDownloadTaskId = null;
              _loadModelInfo();
              widget.onModelStatusChanged();
            }
          });
        },
      );

      setState(() {
        _currentDownloadTaskId = taskId;
      });
    } catch (e) {
      _showErrorDialog('Download failed: $e');
    }
  }

  Future<void> _cancelDownload() async {
    if (_currentDownloadTaskId != null) {
      try {
        await FlutterLeapSdkService.cancelDownload(_currentDownloadTaskId!);
        setState(() {
          _currentDownloadTaskId = null;
          _downloadProgress = 0.0;
          _downloadSpeed = '';
        });
      } catch (e) {
        _showErrorDialog('Failed to cancel download: $e');
      }
    }
  }

  Future<void> _loadModel() async {
    if (_selectedModel == null) return;
    
    try {
      final modelBundle = availableModels[_selectedModel]!;
      await FlutterLeapSdkService.loadModel(
        modelPath: modelBundle,
      );
      
      widget.onModelStatusChanged();
    } catch (e) {
      _showErrorDialog('Failed to load model: $e');
    }
  }

  Future<void> _unloadModel() async {
    try {
      await FlutterLeapSdkService.unloadModel();
      widget.onModelStatusChanged();
    } catch (e) {
      _showErrorDialog('Failed to unload model: $e');
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Model Status Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Model Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  FutureBuilder<bool>(
                    future: FlutterLeapSdkService.checkModelLoaded(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Text('Checking...');
                      }
                      
                      final isLoaded = snapshot.data ?? false;
                      return Row(
                        children: [
                          Icon(
                            isLoaded ? Icons.check_circle : Icons.error,
                            color: isLoaded ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isLoaded 
                              ? 'Model loaded: ${FlutterLeapSdkService.currentModel}'
                              : 'No model loaded',
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Downloaded Models Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Downloaded Models',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (_downloadedModels.isEmpty)
                    const Text('No models downloaded')
                  else
                    ...(_downloadedModels.map((model) => ListTile(
                      leading: const Icon(Icons.folder),
                      title: Text(model),
                      trailing: IconButton(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () => _loadModel(),
                      ),
                    ))),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Download Progress Card
          if (_currentDownloadTaskId != null) ...[
            Card(
              elevation: 4,
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.download,
                          color: Colors.blue.shade600,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Downloading ${_selectedModel ?? 'Model'}...',
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    // Progress bar with better styling
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _downloadProgress / 100,
                        minHeight: 8,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _downloadProgress >= 100 ? Colors.green : Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // Progress text with better formatting
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_downloadProgress.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                        if (_downloadSpeed.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _downloadSpeed,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                    
                    // Cancel button during download
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _cancelDownload,
                        icon: const Icon(Icons.cancel, size: 18),
                        label: const Text('Cancel Download'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade600,
                          side: BorderSide(color: Colors.red.shade300),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          // Actions Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Actions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  
                  // Model selection dropdown
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Model to Download:',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          DropdownButton<String>(
                            value: _selectedModel,
                            isExpanded: true,
                            onChanged: _currentDownloadTaskId != null ? null : (String? value) {
                              setState(() {
                                _selectedModel = value;
                              });
                            },
                            items: availableModels.keys.map((String model) {
                              return DropdownMenuItem<String>(
                                value: model,
                                child: Text(model),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _currentDownloadTaskId != null ? null : _downloadModel,
                      icon: const Icon(Icons.download),
                      label: Text('Download ${_selectedModel ?? 'Model'}'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _downloadedModels.isEmpty ? null : _loadModel,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Load Model'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  FutureBuilder<bool>(
                    future: FlutterLeapSdkService.checkModelLoaded(),
                    builder: (context, snapshot) {
                      final isLoaded = snapshot.data ?? false;
                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: !isLoaded ? null : _unloadModel,
                          icon: const Icon(Icons.eject),
                          label: const Text('Unload Model'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                        ),
                      );
                    },
                  ),
                  
                  if (_currentDownloadTaskId != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _cancelDownload,
                        icon: const Icon(Icons.cancel),
                        label: const Text('Cancel Download'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // SDK Information Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SDK Information',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('LEAP Flutter SDK Demo'),
                  const Text('Features:'),
                  const SizedBox(height: 4),
                  const Text('• Basic conversation chat'),
                  const Text('• Function calling with sample functions'),
                  const Text('• Model download and management'),
                  const SizedBox(height: 8),
                  const Text(
                    'This demo showcases the main features of the LEAP SDK for Flutter. Each tab demonstrates different capabilities.',
                    style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
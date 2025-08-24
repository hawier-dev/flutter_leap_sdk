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
    _tabController = TabController(length: 4, vsync: this);
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
            Tab(icon: Icon(Icons.stream), text: 'Streaming'),
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
                StreamingTab(isModelLoaded: _isModelLoaded),
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
        name: 'calculate',
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

// Streaming Tab - Demonstrates structured streaming responses
class StreamingTab extends StatefulWidget {
  final bool isModelLoaded;

  const StreamingTab({
    super.key,
    required this.isModelLoaded,
  });

  @override
  State<StreamingTab> createState() => _StreamingTabState();
}

class _StreamingTabState extends State<StreamingTab> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  Conversation? _conversation;
  List<Map<String, dynamic>> _streamingMessages = [];
  bool _isStreaming = false;

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
        systemPrompt: "You are a helpful AI assistant. Provide detailed, structured responses when appropriate.",
        generationOptions: GenerationOptions.creative(),
      );
      
      setState(() {
        _conversation = conversation;
        _streamingMessages = [];
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
      _streamingMessages.add({
        'type': 'user',
        'content': userMessage,
        'timestamp': DateTime.now(),
      });
      _isStreaming = true;
    });
    
    _scrollToBottom();
    
    try {
      String fullResponse = '';
      String reasoning = '';
      List<LeapFunctionCall> functionCalls = [];
      
      await for (final response in _conversation!.generateResponseStructured(userMessage)) {
        setState(() {
          if (response is MessageResponseChunk) {
            fullResponse += response.text;
            _updateOrAddAssistantMessage(fullResponse, reasoning, functionCalls, false);
          } else if (response is MessageResponseReasoningChunk) {
            reasoning += response.reasoning;
            _updateOrAddAssistantMessage(fullResponse, reasoning, functionCalls, false);
          } else if (response is MessageResponseFunctionCalls) {
            functionCalls.addAll(response.functionCalls);
            _updateOrAddAssistantMessage(fullResponse, reasoning, functionCalls, false);
          } else if (response is MessageResponseComplete) {
            _updateOrAddAssistantMessage(fullResponse, reasoning, functionCalls, true);
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _streamingMessages.add({
          'type': 'assistant',
          'content': 'Error: ${e.toString()}',
          'timestamp': DateTime.now(),
          'isComplete': true,
        });
      });
    } finally {
      setState(() {
        _isStreaming = false;
      });
      _scrollToBottom();
    }
  }

  void _updateOrAddAssistantMessage(String content, String reasoning, List<LeapFunctionCall> functionCalls, bool isComplete) {
    final existingIndex = _streamingMessages.lastIndexWhere((msg) => msg['type'] == 'assistant');
    
    if (existingIndex != -1) {
      _streamingMessages[existingIndex] = {
        'type': 'assistant',
        'content': content,
        'reasoning': reasoning.isEmpty ? null : reasoning,
        'functionCalls': functionCalls.isEmpty ? null : functionCalls,
        'timestamp': _streamingMessages[existingIndex]['timestamp'],
        'isComplete': isComplete,
      };
    } else {
      _streamingMessages.add({
        'type': 'assistant',
        'content': content,
        'reasoning': reasoning.isEmpty ? null : reasoning,
        'functionCalls': functionCalls.isEmpty ? null : functionCalls,
        'timestamp': DateTime.now(),
        'isComplete': isComplete,
      });
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
              'Please load a model in the Settings tab to see streaming',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Info panel
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Structured Streaming Demo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              Text(
                'This shows real-time streaming with chunk-by-chunk updates, reasoning content, and function calls.',
                style: TextStyle(fontSize: 12),
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
                    Icon(Icons.stream, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    const Text(
                      'Streaming Demo',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Watch responses appear in real-time\nas they are generated by the model.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _streamingMessages.length + (_isStreaming ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _streamingMessages.length && _isStreaming) {
                    return _buildStreamingIndicator();
                  }
                  
                  final message = _streamingMessages[index];
                  return _buildStreamingMessageBubble(message);
                },
              ),
        ),
        
        // Input
        _buildMessageInput(),
      ],
    );
  }

  Widget _buildStreamingMessageBubble(Map<String, dynamic> message) {
    final isUser = message['type'] == 'user';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.green.shade100,
              child: Icon(Icons.stream, size: 16, color: Colors.green.shade700),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? Colors.blue.shade500 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20).copyWith(
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                  ),
                  child: Text(
                    message['content'] ?? '',
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                ),
                
                if (!isUser && message['reasoning'] != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.psychology, size: 16, color: Colors.amber.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Reasoning:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message['reasoning'],
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                
                if (!isUser && message['functionCalls'] != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.functions, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 4),
                            Text(
                              'Function Calls:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ...((message['functionCalls'] as List<LeapFunctionCall>).map((call) => 
                          Text(
                            '${call.name}(${call.arguments.entries.map((e) => '${e.key}: ${e.value}').join(', ')})',
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        )),
                      ],
                    ),
                  ),
                ],
              ],
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

  Widget _buildStreamingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.green.shade100,
            child: Icon(Icons.stream, size: 16, color: Colors.green.shade700),
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
                const Text('Streaming...'),
                const SizedBox(width: 8),
                ...List.generate(3, (index) => 
                  Container(
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(right: index < 2 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: Colors.green.shade400,
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
                icon: const Icon(Icons.stream),
                label: const Text('Start Streaming Demo'),
              ),
            )
          else ...[
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Ask for a detailed explanation...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade100,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
                enabled: !_isStreaming,
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              onPressed: _isStreaming ? null : _sendMessage,
              mini: true,
              child: Icon(_isStreaming ? Icons.hourglass_empty : Icons.send),
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

  @override
  void initState() {
    super.initState();
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
    try {
      setState(() {
        _downloadProgress = 0.0;
        _downloadSpeed = '';
      });

      final taskId = await FlutterLeapSdkService.downloadModel(
        modelName: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
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
    try {
      await FlutterLeapSdkService.loadModel(
        modelPath: 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle',
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
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Download Progress',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgress / 100),
                    const SizedBox(height: 8),
                    Text('${_downloadProgress.toInt()}% - $_downloadSpeed'),
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
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _currentDownloadTaskId != null ? null : _downloadModel,
                      icon: const Icon(Icons.download),
                      label: const Text('Download Model (LFM2-350M)'),
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
                  const Text('• Structured streaming responses'),
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
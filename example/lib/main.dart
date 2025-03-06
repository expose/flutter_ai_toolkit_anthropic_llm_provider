import 'package:flutter/material.dart';
import 'package:flutter_ai_anthropic_llm_provider/flutter_ai_anthropic_llm_provider.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anthropic Provider Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: ChangeNotifierProvider<AnthropicLLMProvider>(
        create: (_) => AnthropicLLMProvider.fromApiKey(
          apiKey:
              '', // Replace with your actual API key
          model:
              'claude-3-haiku-20240307', // Using a fast model for the example
        ),
        child: const ChatPage(),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _response = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _showModelInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        final provider = Provider.of<AnthropicLLMProvider>(context);
        return AlertDialog(
          title: const Text('Model Information'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildInfoSection(
                  'Current Model',
                  provider.defaultModel,
                ),
                const SizedBox(height: 16),
                _buildInfoSection(
                  'API Version',
                  '2024-01-01',
                ),
                const Divider(height: 32),
                const Text(
                  'Available Models',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildModelCard(
                  'claude-3-opus-20240229',
                  'Most capable model, ideal for complex tasks requiring deep analysis',
                ),
                _buildModelCard(
                  'claude-3-sonnet-20240229',
                  'Balanced model, great for most tasks with good performance',
                ),
                _buildModelCard(
                  'claude-3-haiku-20240307',
                  'Fastest model, perfect for quick responses and simple tasks',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildModelCard(String name, String description) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _sendMessage() async {
    final message = _controller.text.trim();
    if (message.isEmpty) return;

    setState(() {
      _isLoading = true;
      _response = '';
    });

    _controller.clear();

    final provider = Provider.of<AnthropicLLMProvider>(context, listen: false);

    try {
      await for (final chunk in provider.sendMessageStream(message)) {
        setState(() {
          _response += chunk;
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        _response = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AnthropicLLMProvider>(context);
    final history = provider.history.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anthropic Chat Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showModelInfo(context),
            tooltip: 'Model Information',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              provider.clearHistory();
              setState(() {
                _response = '';
              });
            },
            tooltip: 'Clear chat history',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16.0),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final message = history[index];
                return _buildMessageBubble(
                  text: message.text ?? '',
                  isUser: message.origin.isUser,
                );
              },
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: LinearProgressIndicator(),
            ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                      border: OutlineInputBorder(),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8.0),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({required String text, required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.secondary.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16.0),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}

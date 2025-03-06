import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anthropic_dart/anthropic_dart.dart' as anthropic_dart;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:http/http.dart' as http;

/// A custom LLM provider implementation for Anthropic's Claude using the flutter_ai_toolkit
/// 
/// This provider allows you to use Anthropic's Claude models with the flutter_ai_toolkit package.
/// It supports streaming responses, attachment handling, and chat history management.
/// 
/// Example usage:
/// ```dart
/// final provider = AnthropicLLMProvider.fromApiKey(
///   apiKey: 'your-api-key',
///   model: 'claude-3-opus-20240229',
/// );
/// 
/// // Generate a one-time response
/// final response = await provider.generateStream('Hello, Claude!').toList();
/// 
/// // Or use in a chat context
/// provider.sendMessageStream('Tell me about coffee brewing').listen(
///   (chunk) => print('Received chunk: $chunk'),
///   onError: (e) => print('Error: $e'),
///   onDone: () => print('Stream complete'),
/// );
/// ```
class AnthropicLLMProvider extends LlmProvider with ChangeNotifier {
  /// The Anthropic API client
  final anthropic_dart.AnthropicService client;

  /// The default model to use for requests
  final String defaultModel;

  /// Chat history storage
  final List<ChatMessage> _history = [];

  /// API key for Anthropic
  final String apiKey;

  /// Base URL for Anthropic API
  static const String _baseUrl = 'https://api.anthropic.com/v1/messages';

  /// Dio client for making HTTP requests
  late Dio _dio;

  /// Cancel token for request cancellation
  CancelToken? cancelToken;

  /// Setter for Dio client, exposed for testing
  set dioClient(Dio client) => _dio = client;

  /// Creates a new AnthropicLLMProvider
  ///
  /// [client] is the Anthropic API client
  /// [defaultModel] is the default model to use (e.g., 'claude-3-opus-20240229')
  /// [apiKey] is the Anthropic API key
  AnthropicLLMProvider({
    required this.client,
    required this.defaultModel,
    required this.apiKey,
  }) {
    debugPrint('AnthropicLLMProvider: Constructor called');
    debugPrint(
        'AnthropicLLMProvider: API key provided - empty: ${apiKey.isEmpty}, length: ${apiKey.length}');
    debugPrint('AnthropicLLMProvider: Model: $defaultModel');

    _dio = Dio();
  }

  /// Factory constructor to create a provider from an API key
  factory AnthropicLLMProvider.fromApiKey({
    required String apiKey,
    String model = 'claude-3-opus-20240229',
  }) {
    debugPrint('AnthropicLLMProvider.fromApiKey: Creating provider');
    debugPrint(
        'AnthropicLLMProvider.fromApiKey: API key provided - empty: ${apiKey.isEmpty}, length: ${apiKey.length}');
    debugPrint('AnthropicLLMProvider.fromApiKey: Model: $model');

    // Validate API key
    if (apiKey.isEmpty) {
      debugPrint(
          'AnthropicLLMProvider.fromApiKey: Error - Empty API key provided');
      throw Exception('API key cannot be empty');
    }

    // Trim API key to remove any accidental whitespace
    final trimmedApiKey = apiKey.trim();

    if (trimmedApiKey.isEmpty) {
      debugPrint(
          'AnthropicLLMProvider.fromApiKey: Error - API key contains only whitespace');
      throw Exception('API key cannot be empty');
    }

    final client = anthropic_dart.AnthropicService(trimmedApiKey, model: model);
    return AnthropicLLMProvider(
      client: client,
      defaultModel: model,
      apiKey: trimmedApiKey,
    );
  }

  @override
  Stream<String> generateStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) async* {
    debugPrint(
        'AnthropicLLMProvider.generateStream: Called with prompt length: ${prompt.length}');
    debugPrint(
        'AnthropicLLMProvider.generateStream: Current API key - empty: ${apiKey.isEmpty}, length: ${apiKey.length}');

    // Validate API key first
    if (apiKey.isEmpty) {
      debugPrint(
          'AnthropicLLMProvider.generateStream: API key is empty, throwing exception');
      throw Exception(
          'API key not configured. Please set up your API key in settings.');
    }

    try {
      debugPrint(
          'Generating stream response from Anthropic with model: $defaultModel');
      // Process attachments if any
      final processedContent =
          await _processPromptWithAttachments(prompt, attachments);

      // Use streaming API for real-time responses
      final streamController = StreamController<String>();

      _streamResponse(
        messages: [
          anthropic_dart.Message(role: 'user', content: processedContent),
        ],
        streamController: streamController,
      );

      yield* streamController.stream;
    } catch (e, stackTrace) {
      debugPrint('Error generating response from Anthropic: $e\n$stackTrace');
      throw Exception(
          'Error generating response from Anthropic: ${e.toString()}');
    }
  }

  @override
  Stream<String> sendMessageStream(
    String prompt, {
    Iterable<Attachment> attachments = const [],
  }) async* {
    debugPrint(
        'AnthropicLLMProvider.sendMessageStream: Starting with prompt length: ${prompt.length}');

    // Validate API key first
    if (apiKey.isEmpty) {
      debugPrint(
          'AnthropicLLMProvider.sendMessageStream: Error - Empty API key');
      throw Exception(
          'API key not configured. Please set up your API key in settings.');
    }

    // Validate prompt
    if (prompt.trim().isEmpty) {
      debugPrint(
          'AnthropicLLMProvider.sendMessageStream: Error - Empty prompt');
      throw Exception('Message content cannot be empty.');
    }

    // Check if the last message in history is already this exact user message to avoid duplicates
    bool isDuplicate = false;
    if (_history.isNotEmpty && _history.last.origin.isUser && _history.last.text == prompt) {
      debugPrint('AnthropicLLMProvider.sendMessageStream: Detected duplicate user message, not adding to history');
      isDuplicate = true;
    }
    
    // Create user and LLM messages
    final userMessage = ChatMessage.user(prompt, attachments.toList());
    final llmMessage = ChatMessage.llm();
    
    // Add messages to history (only if not a duplicate)
    if (!isDuplicate) {
      _history.addAll([userMessage, llmMessage]);
      notifyListeners();
    }

    try {
      debugPrint(
          'AnthropicLLMProvider.sendMessageStream: Processing message for Anthropic API');
      // Process attachments if any
      final processedContent =
          await _processPromptWithAttachments(prompt, attachments);

      // Convert history to Anthropic format
      final anthropicMessages = _convertChatHistoryToAnthropicMessages();

      // Replace the last user message content with processed content (including attachments)
      if (anthropicMessages.isNotEmpty &&
          anthropicMessages.last.role == 'user') {
        anthropicMessages.last = anthropic_dart.Message(
          role: 'user',
          content: processedContent,
        );
      }

      debugPrint('AnthropicLLMProvider.sendMessageStream: Setting up stream');
      // Use streaming API for real-time responses
      final streamController = StreamController<String>();
      final buffer = StringBuffer();

      _streamResponse(
        messages: anthropicMessages,
        streamController: streamController,
        onData: (chunk) {
          buffer.write(chunk);
          // Update the last message in history if it's from LLM
          if (_history.isNotEmpty && _history.last.origin.isLlm) {
            _history.last.text = buffer.toString();
            notifyListeners();
          }
        },
        onError: (error) {
          // Handle errors during streaming
          debugPrint(
              'AnthropicLLMProvider.sendMessageStream: Stream error: $error');
          // Append error to the last message in history if it's from LLM
          if (_history.isNotEmpty && _history.last.origin.isLlm) {
            _history.last.append('\nError: ${error.toString()}');
            notifyListeners();
          }
        },
      );

      debugPrint('AnthropicLLMProvider.sendMessageStream: Yielding stream');
      yield* streamController.stream;
    } catch (e, stackTrace) {
      debugPrint('AnthropicLLMProvider.sendMessageStream: Error: $e');
      debugPrint(
          'AnthropicLLMProvider.sendMessageStream: Stack trace: $stackTrace');
      // Append error to the last message in history if it's from LLM
      if (_history.isNotEmpty && _history.last.origin.isLlm) {
        _history.last.append('\nError: ${e.toString()}');
        notifyListeners();
      }
      throw Exception('Error sending message to Anthropic: ${e.toString()}');
    }
  }

  /// Converts ChatMessage history to Anthropic API format
  List<anthropic_dart.Message> _convertChatHistoryToAnthropicMessages() {
    final result = <anthropic_dart.Message>[];
    final processedContents = <String>{}; // Set to track already processed content
    String? lastRole;

    for (final message in _history) {
      // Skip empty messages or messages without text
      if (message.text == null || message.text!.isEmpty) continue;
      
      // Skip duplicated consecutive messages with the same role and content
      final currentRole = message.origin.isUser ? 'user' : 'assistant';
      final messageContent = message.text ?? '';
      
      // Create a unique key combining role and content to detect duplicates
      final contentKey = '$currentRole:$messageContent';
      
      // Skip if this exact content from the same role was already added
      if (processedContents.contains(contentKey)) {
        debugPrint('AnthropicLLMProvider._convertChatHistoryToAnthropicMessages: Skipping duplicate message');
        continue;
      }
      
      // Skip if we have consecutive messages with the same role (Anthropic API requirement)
      if (lastRole == currentRole) {
        debugPrint('AnthropicLLMProvider._convertChatHistoryToAnthropicMessages: Skipping consecutive message with same role');
        continue;
      }
      
      // Add to processed set and update last role
      processedContents.add(contentKey);
      lastRole = currentRole;

      if (message.origin.isUser) {
        result.add(anthropic_dart.Message(
          role: 'user',
          content: messageContent,
        ));
      } else if (message.origin.isLlm) {
        result.add(anthropic_dart.Message(
          role: 'assistant',
          content: messageContent,
        ));
      }
    }

    return result;
  }

  /// Process prompt with attachments to create Anthropic-compatible content
  Future<String> _processPromptWithAttachments(
    String prompt,
    Iterable<Attachment> attachments,
  ) async {
    // If no attachments, return the prompt as is
    if (attachments.isEmpty) {
      return prompt;
    }

    // For now, we'll just append a note about attachments since the current
    // anthropic_dart package doesn't support image attachments directly
    // In a real implementation, you would convert images to base64 and use
    // the appropriate Anthropic API format for multimodal content

    final attachmentDescriptions = attachments.map((attachment) {
      if (attachment is ImageFileAttachment) {
        return '[Image attachment: ${attachment.name}]';
      } else if (attachment is FileAttachment) {
        return '[File attachment: ${attachment.name}]';
      } else if (attachment is LinkAttachment) {
        return '[Link: ${attachment.url}]';
      } else {
        return '[Unknown attachment: ${attachment.name}]';
      }
    }).join('\n');

    return '$prompt\n\n$attachmentDescriptions';
  }

  /// Stream response from Anthropic API
  void _streamResponse({
    required List<anthropic_dart.Message> messages,
    required StreamController<String> streamController,
    void Function(String)? onData,
    void Function(Object)? onError,
  }) async {
    // Validate API key
    if (apiKey.isEmpty) {
      final error = Exception(
          'API key not configured. Please set up your API key in settings.');
      debugPrint('AnthropicLLMProvider._streamResponse: Error - Empty API key');
      onError?.call(error);
      streamController.addError(error);
      streamController.close();
      return;
    }

    // Validate messages
    if (messages.isEmpty) {
      final error = Exception('No messages to send.');
      debugPrint(
          'AnthropicLLMProvider._streamResponse: Error - Empty messages');
      onError?.call(error);
      streamController.addError(error);
      streamController.close();
      return;
    }

    try {
      debugPrint(
          'AnthropicLLMProvider._streamResponse: Sending request to Anthropic API with model: $defaultModel');
      final requestBody = {
        'model': defaultModel,
        'messages': messages.map((m) => m.toJson()).toList(),
        'stream': true,
        'max_tokens': 4096,
      };

      debugPrint('AnthropicLLMProvider._streamResponse: Request body prepared');

      // Log the request body
      debugPrint(
          'AnthropicLLMProvider._streamResponse: Request body: ${jsonEncode(requestBody)}');

      // Log complete request details
      debugPrint('AnthropicLLMProvider._streamResponse: Request details:');
      debugPrint('URL: $_baseUrl');
      debugPrint('Headers: ${{
        'anthropic-version': '2024-01-01',
        'x-anthropic-api-key': '[REDACTED]',
        'content-type': 'application/json',
      }}');
      debugPrint('Body: ${jsonEncode(requestBody)}');

      // Add timeout to prevent hanging requests
      _dio.options.connectTimeout = const Duration(seconds: 30);
      _dio.options.receiveTimeout = const Duration(seconds: 60);

      // Add logging interceptor
      _dio.interceptors.clear(); // Clear any existing interceptors
      _dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          debugPrint('\n🌐 Request:');
          debugPrint('URL: ${options.uri}');
          debugPrint('Method: ${options.method}');
          debugPrint('Headers: ${options.headers}');
          debugPrint('Data: ${options.data}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint('\n✅ Response:');
          debugPrint('Status code: ${response.statusCode}');
          debugPrint('Headers: ${response.headers}');
          return handler.next(response);
        },
        onError: (error, handler) {
          debugPrint('\n❌ Error:');
          debugPrint('Status code: ${error.response?.statusCode}');
          debugPrint('Headers: ${error.response?.headers}');
          debugPrint('Data: ${error.response?.data}');
          debugPrint('Message: ${error.message}');
          return handler.next(error);
        },
      ));

      final response = await _dio.post(
        _baseUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'anthropic-version': '2023-06-01',
            'x-api-key': apiKey,
            'content-type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
        cancelToken: cancelToken,
      );

      debugPrint(
          'AnthropicLLMProvider._streamResponse: Response received, status: ${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint(
            'AnthropicLLMProvider._streamResponse: Error - Non-200 status code: ${response.statusCode}');
        
        // Try to get more detailed error information from response headers
        String errorDetails = '';
        if (response.headers.map.containsKey('x-error-type')) {
          errorDetails = ' (${response.headers.value('x-error-type')})';
        }
        
        // Handle 400 Bad Request more specifically
        if (response.statusCode == 400) {
          // Try to read the error body
          try {
            final errorStream = (response.data as ResponseBody).stream;
            final errorBytes = await errorStream.first;
            final errorBody = utf8.decode(errorBytes);
            
            debugPrint('AnthropicLLMProvider._streamResponse: Error body: $errorBody');
            
            // Try to parse as JSON for structured error
            try {
              final errorJson = jsonDecode(errorBody);
              if (errorJson is Map && errorJson.containsKey('error')) {
                _handleErrorResponse(errorJson, onError, streamController);
                streamController.close();
                return;
              }
            } catch (jsonError) {
              // If not JSON, use as plain text error
              errorDetails = ': $errorBody';
            }
          } catch (streamError) {
            debugPrint('AnthropicLLMProvider._streamResponse: Error reading error stream: $streamError');
          }
          
          final badRequestMsg = 'Bad Request - The API rejected your request$errorDetails';
          debugPrint('AnthropicLLMProvider._streamResponse: $badRequestMsg');
          
          final error = Exception(badRequestMsg);
          onError?.call(error);
          streamController.addError(error);
          streamController.close();
          return;
        }
        
        final error = Exception('API returned status code ${response.statusCode}$errorDetails');
        onError?.call(error);
        streamController.addError(error);
        streamController.close();
        return;
      }

      final responseStream = (response.data as ResponseBody).stream;

      debugPrint(
          'AnthropicLLMProvider._streamResponse: Processing response stream');

      // Simplified unified stream handling approach
      Stream<String> lineStream;

      try {
        // Convert Uint8List stream to String stream
        lineStream = responseStream
            .map((event) => utf8.decode(event))
            .transform(const LineSplitter());

        debugPrint(
            'AnthropicLLMProvider._streamResponse: Stream conversion successful');
      } catch (e) {
        debugPrint(
            'AnthropicLLMProvider._streamResponse: Error setting up stream: $e');
        final error = Exception('Error setting up stream: $e');
        onError?.call(error);
        streamController.addError(error);
        streamController.close();
        return;
      }

      try {
        // Process the unified line stream with buffer for handling split JSON
        final lineBuffer = StringBuffer();
        bool isBuffering = false;

        await for (final line in lineStream) {
          if (line.isEmpty) continue;

          if (line.startsWith('data: ') && line != 'data: [DONE]') {
            final jsonData = line.substring(6);

            // Try to parse the JSON to see if it's complete
            try {
              jsonDecode(jsonData);
              // If we get here, the JSON is valid, so process it directly
              if (isBuffering) {
                // We were buffering, but this is a new complete JSON object
                // Process the buffer first if it's not empty
                if (lineBuffer.isNotEmpty) {
                  await _processDataLine(
                      lineBuffer.toString(), streamController, onData, onError);
                  lineBuffer.clear();
                }
                isBuffering = false;
              }
              await _processDataLine(
                  jsonData, streamController, onData, onError);
            } catch (e) {
              // JSON is incomplete, buffer it
              if (!isBuffering) {
                // Start a new buffer
                lineBuffer.clear();
                isBuffering = true;
              }
              lineBuffer.write(jsonData);

              // Try to parse the buffer to see if it's now complete
              try {
                final bufferData = lineBuffer.toString();
                jsonDecode(bufferData);
                // Buffer is now a valid JSON, process it
                await _processDataLine(
                    bufferData, streamController, onData, onError);
                lineBuffer.clear();
                isBuffering = false;
              } catch (e) {
                // Buffer is still incomplete, continue buffering
                debugPrint(
                    'AnthropicLLMProvider._streamResponse: Buffering incomplete JSON');
              }
            }
          } else if (line.contains('error')) {
            // Handle error lines
            if (isBuffering) {
              // Clear the buffer if we encounter an error
              lineBuffer.clear();
              isBuffering = false;
            }
            await _handleErrorLine(line, onError, streamController);
          } else if (line.startsWith('{') || line.startsWith('[')) {
            // This might be a JSON line without the 'data:' prefix
            // Add it to the buffer if we're buffering
            if (isBuffering) {
              lineBuffer.write(line);

              // Try to parse the buffer to see if it's now complete
              try {
                final bufferData = lineBuffer.toString();
                jsonDecode(bufferData);
                // Buffer is now a valid JSON, process it
                await _processDataLine(
                    bufferData, streamController, onData, onError);
                lineBuffer.clear();
                isBuffering = false;
              } catch (e) {
                // Buffer is still incomplete, continue buffering
                debugPrint(
                    'AnthropicLLMProvider._streamResponse: Buffering incomplete JSON');
              }
            } else {
              // Try to process it directly
              try {
                final data = jsonDecode(line);
                String? extractedText = _extractTextFromEvent(data);
                if (extractedText != null && extractedText.isNotEmpty) {
                  streamController.add(extractedText);
                  onData?.call(extractedText);
                  notifyListeners();
                }
              } catch (e) {
                // Ignore parsing errors for non-data lines
                debugPrint(
                    'AnthropicLLMProvider._streamResponse: Error parsing possible JSON line: $e');
              }
            }
          }
        }

        // Process any remaining buffered content
        if (isBuffering && lineBuffer.isNotEmpty) {
          try {
            final bufferData = lineBuffer.toString();
            jsonDecode(bufferData); // Check if it's valid JSON
            await _processDataLine(
                bufferData, streamController, onData, onError);
          } catch (e) {
            // If the buffer is still invalid JSON at the end, try to extract any text
            debugPrint(
                'AnthropicLLMProvider._streamResponse: Final buffer is not valid JSON: $e');
            final bufferData = lineBuffer.toString();
            if (bufferData.isNotEmpty &&
                !bufferData.startsWith('{') &&
                !bufferData.startsWith('[')) {
              streamController.add(bufferData);
              onData?.call(bufferData);
              notifyListeners();
            }
          }
        }

        debugPrint(
            'AnthropicLLMProvider._streamResponse: Stream completed successfully');
        streamController.close();
      } catch (e) {
        debugPrint(
            'AnthropicLLMProvider._streamResponse: Error in stream processing: $e');
        final error = Exception('Error processing stream: $e');
        onError?.call(error);
        streamController.addError(error);
        streamController.close();
      }
    } catch (e, stackTrace) {
      debugPrint(
          'AnthropicLLMProvider._streamResponse: Error streaming response: $e');
      debugPrint(
          'AnthropicLLMProvider._streamResponse: Stack trace: $stackTrace');
      onError?.call(e);
      streamController.addError(e);
      streamController.close();
    }
  }

  /// Process a single data line from the stream
  Future<void> _processDataLine(
    String jsonData,
    StreamController<String> streamController,
    void Function(String)? onData,
    void Function(Object)? onError,
  ) async {
    if (jsonData.isEmpty) return;

    try {
      final data = jsonDecode(jsonData);

      // Handle error responses
      if (data.containsKey('error')) {
        _handleErrorResponse(
            data as Map<dynamic, dynamic>, onError, streamController);
        return;
      }

      // Extract text based on event type
      String? extractedText = _extractTextFromEvent(data);

      if (extractedText != null && extractedText.isNotEmpty) {
        streamController.add(extractedText);
        onData?.call(extractedText);
        notifyListeners();
      }
    } catch (e) {
      debugPrint(
          'AnthropicLLMProvider._processDataLine: Error parsing JSON: $e');
      // Try to extract any plain text if JSON parsing fails
      if (jsonData.isNotEmpty &&
          !jsonData.startsWith('{') &&
          !jsonData.startsWith('[')) {
        // This might be plain text content
        streamController.add(jsonData);
        onData?.call(jsonData);
        notifyListeners();
      }
    }
  }

  /// Extract text content from different event types
  String? _extractTextFromEvent(Map<dynamic, dynamic> data) {
    // Handle various event types
    if (data['type'] == 'content_block_delta' &&
        data['delta'].containsKey('text')) {
      return data['delta']['text'] as String;
    } else if (data['type'] == 'content_block_start' &&
        data.containsKey('content_block') &&
        data['content_block'] is Map &&
        data['content_block'].containsKey('text')) {
      return data['content_block']['text'] as String;
    } else if (data.containsKey('content') && data['content'] is List) {
      // Handle non-streaming format with content blocks
      final content = data['content'] as List;
      final textParts = <String>[];

      for (final block in content) {
        if (block is Map && block.containsKey('text')) {
          textParts.add(block['text'] as String);
        }
      }

      return textParts.join();
    } else if (data.containsKey('completion')) {
      // Handle legacy format with direct completion field
      final completion = data['completion'];
      if (completion is String) {
        return completion;
      }
    }

    // Log unrecognized data formats for debugging
    if (data.containsKey('type')) {
      debugPrint(
          'AnthropicLLMProvider._extractTextFromEvent: Received event type: ${data['type']}');
    } else {
      debugPrint(
          'AnthropicLLMProvider._extractTextFromEvent: Unrecognized data structure: ${data.keys.join(', ')}');
    }

    return null;
  }

  /// Handle error responses from the API
  void _handleErrorResponse(
      Map<dynamic, dynamic> data,
      void Function(Object)? onError,
      StreamController<String> streamController) {
    var errorMessage = 'Unknown API error';

    if (data['error'] is Map) {
      // Extract structured error information
      final errorObj = data['error'] as Map<dynamic, dynamic>;
      final errorType = errorObj['type'] ?? 'unknown_error';
      final errorDetails = errorObj['message'] ?? '';
      
      // Add any additional error details if available
      final errorCode = errorObj['code'] ?? '';
      final param = errorObj['param'] ?? '';
      final additionalDetails = [];
      
      if (errorCode.toString().isNotEmpty) {
        additionalDetails.add('Code: $errorCode');
      }
      
      if (param.toString().isNotEmpty) {
        additionalDetails.add('Parameter: $param');
      }
      
      final detailsStr = additionalDetails.isNotEmpty 
          ? ' (${additionalDetails.join(', ')})' 
          : '';
      
      errorMessage = 'API error ($errorType$detailsStr): $errorDetails';
      
      // Add additional user-friendly guidance for common error types
      if (errorType == 'invalid_request_error') {
        errorMessage += '\n\nThis usually indicates a problem with the format of your request. Check your API key, model name, and request parameters.';
      } else if (errorType == 'authentication_error') {
        errorMessage += '\n\nPlease verify your API key is correct and active.';
      } else if (errorType == 'rate_limit_error') {
        errorMessage += '\n\nYou have exceeded your current rate limit. Please wait before retrying or contact Anthropic to increase your quota.';
      } else if (errorType == 'permission_error') {
        errorMessage += '\n\nYour account does not have permission to use this model or feature. Contact Anthropic to request access.';
      }
    } else if (data['error'] is String) {
      // Simple string error
      errorMessage = 'API error: ${data['error']}';
    }

    debugPrint('AnthropicLLMProvider._handleErrorResponse: $errorMessage');
    final error = Exception(errorMessage);
    onError?.call(error);
    streamController.addError(error);
  }

  /// Handle error lines from the stream
  Future<void> _handleErrorLine(String line, void Function(Object)? onError,
      StreamController<String> streamController) async {
    try {
      // First try to parse as JSON
      final errorData = jsonDecode(line);
      if (errorData is Map<dynamic, dynamic>) {
        _handleErrorResponse(errorData, onError, streamController);
      } else {
        final errorMessage = 'API error: $line';
        final error = Exception(errorMessage);
        onError?.call(error);
        streamController.addError(error);
      }
    } catch (e) {
      // If JSON parsing fails, extract error information as plain text
      debugPrint(
          'AnthropicLLMProvider._handleErrorLine: Error parsing error JSON: $e');
      final errorMessage =
          'API error: ${line.contains('error') ? line.substring(line.indexOf('error')) : line}';
      final error = Exception(errorMessage);
      onError?.call(error);
      streamController.addError(error);
    }
  }

  @override
  Iterable<ChatMessage> get history => _history;

  @override
  set history(Iterable<ChatMessage> history) {
    _history.clear();
    _history.addAll(history);
    notifyListeners();
  }

  @override
  void clearHistory() {
    _history.clear();
    notifyListeners();
  }
}

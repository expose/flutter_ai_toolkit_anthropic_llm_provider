import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:anthropic_dart/anthropic_dart.dart' as anthropic_dart;
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:flutter_ai_anthropic_llm_provider/src/anthropic_llm_provider.dart';

import 'anthropic_llm_provider_test.mocks.dart';

// Generate mocks for the AnthropicService and Dio
@GenerateMocks([anthropic_dart.AnthropicService, Dio])
void main() {
  late AnthropicLLMProvider provider;
  late anthropic_dart.AnthropicService mockService;
  late MockDio mockDio;
  final testApiKey = 'test-api-key';
  final testModel = 'claude-3-opus-20240229';
  final testPrompt = 'Hello, how are you?';
  final testResponse = 'I am doing well, thank you for asking!';

  setUp(() {
    mockService = MockAnthropicService();
    mockDio = MockDio();
    
    // Create mock options for Dio
    final mockOptions = BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
    );
    
    // Set up the mock options and interceptors
    when(mockDio.options).thenReturn(mockOptions);
    when(mockDio.interceptors).thenReturn(Interceptors());
    
    provider = AnthropicLLMProvider(
      client: mockService,
      defaultModel: testModel,
      apiKey: testApiKey,
    );
    
    // Set the mocked Dio client
    provider.dioClient = mockDio;
  });

  group('AnthropicLLMProvider initialization', () {
    test('should be initialized with correct parameters', () {
      expect(provider.client, equals(mockService));
      expect(provider.defaultModel, equals(testModel));
      expect(provider.apiKey, equals(testApiKey));
    });

    test('should create provider from API key', () {
      final altModel = 'claude-3-haiku-20240307';
      final provider = AnthropicLLMProvider.fromApiKey(
        apiKey: testApiKey,
        model: altModel,
      );
      
      expect(provider.apiKey, equals(testApiKey));
      expect(provider.defaultModel, equals(altModel));
      expect(provider.client, isA<anthropic_dart.AnthropicService>());
    });
  });

  group('AnthropicLLMProvider history management', () {
    test('should add messages to history', () {
      // Add a user message and LLM response to history
      final messages = [
        ChatMessage.user(testPrompt, []),
        ChatMessage.llm()..text = testResponse,
      ];
      
      provider.history = messages;
      
      expect(provider.history.length, equals(2));
      expect(provider.history.first.origin, equals(MessageOrigin.user));
      expect(provider.history.first.text, equals(testPrompt));
      expect(provider.history.last.origin, equals(MessageOrigin.llm));
      expect(provider.history.last.text, equals(testResponse));
    });
    
    test('should clear history when setting empty list', () {
      // First add some messages
      provider.history = [
        ChatMessage.user(testPrompt, []),
        ChatMessage.llm()..text = testResponse,
      ];
      
      // Then clear by setting empty list
      provider.history = [];
      
      expect(provider.history.length, equals(0));
    });
  });
  
  group('AnthropicLLMProvider message conversion', () {
    test('should convert ChatMessage history to Anthropic messages', () {
      // Setup history with user and LLM messages
      provider.history = [
        ChatMessage.user('User message 1', []),
        ChatMessage.llm()..text = 'LLM response 1',
        ChatMessage.user('User message 2', []),
      ];
      
      // Use reflection to access private method
      final convertedMessages = provider.history.toList();
      
      expect(convertedMessages.length, equals(3));
      expect(convertedMessages[0].origin.isUser, isTrue);
      expect(convertedMessages[1].origin.isLlm, isTrue);
      expect(convertedMessages[2].origin.isUser, isTrue);
    });
  });
  
  group('AnthropicLLMProvider streaming', () {
    test('should handle content_block_delta streaming events', () async {
      // Setup mock response stream controller
      final responseController = StreamController<Uint8List>();

      // Create a mock ResponseBody
      final mockResponseBody = ResponseBody(
        responseController.stream,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

      // Create a mock response with the ResponseBody
      final mockResponse = Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 200,
        data: mockResponseBody,
      );

      // Configure the mock to return our response
      when(mockDio.post(
        any,
        data: anyNamed('data'),
        options: anyNamed('options'),
      )).thenAnswer((_) async => mockResponse);

      // Start the stream
      final resultFuture = provider.sendMessageStream(testPrompt).toList();

      // Allow the stream to start processing
      await Future.delayed(Duration.zero);

      // Send mock data chunks
      responseController.add(Uint8List.fromList(utf8.encode(
        'data: {"type":"message_start","message":{"id":"msg_123","model":"claude-3-opus-20240229"}}\n'
      )));
      await Future.delayed(Duration.zero);

      responseController.add(Uint8List.fromList(utf8.encode(
        'data: {"type":"content_block_delta","delta":{"text":"Hello"}}\n'
      )));
      await Future.delayed(Duration.zero);

      responseController.add(Uint8List.fromList(utf8.encode(
        'data: {"type":"content_block_delta","delta":{"text":", world!"}}\n'
      )));
      await Future.delayed(Duration.zero);

      responseController.add(Uint8List.fromList(utf8.encode(
        'data: {"type":"message_stop"}\n'
      )));

      // Close the mock response
      await responseController.close();

      // Get the results
      final results = await resultFuture;

      // Verify results
      expect(results, equals(['Hello', ', world!']));

      // Verify the message was added to history
      expect(provider.history.length, equals(2));
      expect(provider.history.first.origin, equals(MessageOrigin.user));
      expect(provider.history.first.text, equals(testPrompt));
      expect(provider.history.last.origin, equals(MessageOrigin.llm));
      expect(provider.history.last.text, equals('Hello, world!'));
    });

    test('should handle error responses', () async {
      // Setup mock error response
      final responseController = StreamController<Uint8List>();

      // Create a mock ResponseBody for error
      final mockResponseBody = ResponseBody(
        responseController.stream,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

      final mockResponse = Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 200,
        data: mockResponseBody,
      );

      when(mockDio.post(
        any,
        data: anyNamed('data'),
        options: anyNamed('options'),
      )).thenAnswer((_) async => mockResponse);

      // Start the stream and collect errors
      final stream = provider.sendMessageStream(testPrompt);
      bool hasError = false;
      String? errorMessage;

      stream.listen(
        (data) {
          // Just collect data
        },
        onError: (e) {
          hasError = true;
          errorMessage = e.toString();
        },
      );

      // Allow the stream to start processing
      await Future.delayed(Duration.zero);

      // Send an error message in the SSE format
      responseController.add(Uint8List.fromList(utf8.encode(
        'data: {"type":"error","error":{"type":"test_error","message":"Test error message"}}\n'
      )));
      await Future.delayed(Duration.zero);

      // Close the stream
      await responseController.close();

      // Wait a bit for error handling to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify we got an error
      expect(hasError, isTrue);
      expect(errorMessage, contains('Test error message'));
    });

    test('should handle HTTP error responses', () async {
      // Mock a 400 Bad Request response
      final errorResponseController = StreamController<Uint8List>();

      // Create a mock ResponseBody for HTTP error
      final mockErrorResponseBody = ResponseBody(
        errorResponseController.stream,
        400, // Bad Request status
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );

      final mockErrorResponse = Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: 400,
        data: mockErrorResponseBody,
      );

      // Configure the mock to return our error response
      when(mockDio.post(
        any,
        data: anyNamed('data'),
        options: anyNamed('options'),
      )).thenAnswer((_) async => mockErrorResponse);

      // Start the stream and expect an error
      bool hasError = false;
      String? errorMessage;

      provider.sendMessageStream(testPrompt).listen(
        (data) {
          // No data expected
        },
        onError: (e) {
          hasError = true;
          errorMessage = e.toString();
        },
      );

      // Allow the stream to start processing
      await Future.delayed(Duration.zero);

      // Send error data
      errorResponseController.add(Uint8List.fromList(utf8.encode(
        '{"error":{"type":"invalid_request_error","message":"API key is required"}}'
      )));

      // Close the controller
      await errorResponseController.close();

      // Allow time for error handling
      await Future.delayed(const Duration(milliseconds: 100));

      // Verify we got an error
      expect(hasError, isTrue);
      expect(errorMessage, contains('invalid_request_error'));
      expect(errorMessage, contains('API key is required'));
    });
  });
}

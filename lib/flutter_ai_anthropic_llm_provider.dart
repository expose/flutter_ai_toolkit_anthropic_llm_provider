/// A Flutter package that provides an implementation of the `LlmProvider` interface
/// from `flutter_ai_toolkit` for Anthropic's Claude AI models.
///
/// This package enables seamless integration of Anthropic's Claude models into Flutter
/// applications, providing features such as:
/// - Streaming responses for real-time AI interactions
/// - Chat history management
/// - Support for multiple Claude models
/// - Error handling with detailed messages
/// - Support for attachments (text, images, links)
///
/// Example usage:
/// ```dart
/// // Create a provider instance
/// final provider = AnthropicLLMProvider.fromApiKey(
///   apiKey: 'your-api-key',
///   model: 'claude-3-opus-20240229',
/// );
///
/// // Generate a one-time response
/// final response = await provider.generateStream('Tell me about coffee').toList();
///
/// // Use in a chat context with streaming
/// provider.sendMessageStream('What is the best way to brew espresso?').listen(
///   (chunk) => print('Received chunk: $chunk'),
///   onError: (e) => print('Error: $e'),
///   onDone: () => print('Stream complete'),
/// );
///
/// // Handle attachments
/// final attachments = [
///   ImageFileAttachment(
///     name: 'coffee.jpg',
///     path: '/path/to/coffee.jpg',
///   ),
/// ];
///
/// provider.sendMessageStream(
///   'What kind of coffee is this?',
///   attachments: attachments,
/// ).listen(
///   (chunk) => print('Received chunk: $chunk'),
///   onError: (e) => print('Error: $e'),
/// );
///
/// // Access chat history
/// final history = provider.history;
///
/// // Clear chat history
/// provider.clearHistory();
/// ```
///
/// For more information, see the package documentation at:
/// https://pub.dev/packages/flutter_ai_anthropic_llm_provider
library flutter_ai_anthropic_llm_provider;

export 'src/anthropic_llm_provider.dart';

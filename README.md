# Flutter AI Anthropic LLM Provider

A Flutter package that provides an implementation of the `LlmProvider` interface from `flutter_ai_toolkit` for Anthropic's Claude AI models. This package allows seamless integration of Anthropic's powerful language models into your Flutter applications.

## Features

- 🔄 Streaming responses for real-time AI interactions
- 📝 Chat history management
- 🎯 Support for multiple Claude models (claude-3-opus-20240229, claude-3-haiku-20240307, etc.)
- 🔐 Secure API key handling
- 🌐 Error handling with detailed messages
- 📎 Support for attachments (text, images, links)

## Getting Started

### Prerequisites

- Flutter SDK >=3.0.0
- Dart SDK >=3.0.0
- An API key from Anthropic

### Installation

Add this package to your Flutter project's `pubspec.yaml`:

```yaml
dependencies:
  flutter_ai_anthropic_llm_provider: ^1.0.0
  flutter_ai_toolkit: ^0.6.8
```

Then run:

```bash
flutter pub get
```

### Basic Usage

1. Create an instance of `AnthropicLLMProvider`:

```dart
import 'package:flutter_ai_anthropic_llm_provider/flutter_ai_anthropic_llm_provider.dart';

final provider = AnthropicLLMProvider.fromApiKey(
  apiKey: 'your-api-key',
  model: 'claude-3-opus-20240229', // Optional, defaults to claude-3-opus-20240229
);
```

2. Generate a one-time response:

```dart
final response = await provider.generateStream('Tell me about coffee brewing').toList();
print(response.join()); // Combines all response chunks
```

3. Use in a chat context with streaming:

```dart
provider.sendMessageStream('What is the best way to brew espresso?').listen(
  (chunk) => print('Received chunk: $chunk'),
  onError: (e) => print('Error: $e'),
  onDone: () => print('Stream complete'),
);
```

4. Handle attachments:

```dart
final attachments = [
  ImageFileAttachment(
    name: 'coffee.jpg',
    path: '/path/to/coffee.jpg',
  ),
];

provider.sendMessageStream(
  'What kind of coffee is this?',
  attachments: attachments,
).listen(
  (chunk) => print('Received chunk: $chunk'),
  onError: (e) => print('Error: $e'),
);
```

### Chat History Management

The provider automatically manages chat history:

```dart
// Access chat history
final history = provider.history;

// Clear chat history
provider.clearHistory();

// Set custom history
provider.history = [
  ChatMessage.user('Hello', []),
  ChatMessage.llm()..text = 'Hi there!',
];
```

## Error Handling

The package provides detailed error messages for common issues:

- Invalid API key
- Network errors
- Rate limiting
- Invalid model names
- Malformed requests

Example error handling:

```dart
provider.sendMessageStream('Your prompt').listen(
  (chunk) => print(chunk),
  onError: (e) {
    if (e.toString().contains('API key')) {
      print('Please check your API key configuration');
    } else if (e.toString().contains('rate limit')) {
      print('Rate limit exceeded, please try again later');
    } else {
      print('An error occurred: $e');
    }
  },
);
```

## Advanced Configuration

### Custom Model Selection

```dart
final provider = AnthropicLLMProvider.fromApiKey(
  apiKey: 'your-api-key',
  model: 'claude-3-haiku-20240307', // For faster, more concise responses
);
```

### Timeout Configuration

```dart
final dio = Dio()
  ..options.connectTimeout = const Duration(seconds: 30)
  ..options.receiveTimeout = const Duration(seconds: 60);

final provider = AnthropicLLMProvider.fromApiKey(
  apiKey: 'your-api-key',
)..dioClient = dio;
```

## Testing

The package includes comprehensive tests. Run them with:

```bash
flutter test
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Setup

1. Clone the repository
2. Install dependencies: `flutter pub get`
3. Run tests: `flutter test`
4. Make your changes
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Thanks to the Anthropic team for their excellent Claude AI models
- Built with [flutter_ai_toolkit](https://pub.dev/packages/flutter_ai_toolkit)

import 'package:ag_ui/ag_ui.dart';
import 'package:test/test.dart';

/// Extracts the `source` from any media [ContentPart] part.
PartSource _sourceOf(ContentPart part) => switch (part) {
      ImagePart(:final source) => source,
      AudioPart(:final source) => source,
      VideoPart(:final source) => source,
      DocumentPart(:final source) => source,
      _ => throw StateError('not a media part: ${part.type}'),
    };

/// Extracts the `metadata` from any media [ContentPart] part.
Object? _metadataOf(ContentPart part) => switch (part) {
      ImagePart(:final metadata) => metadata,
      AudioPart(:final metadata) => metadata,
      VideoPart(:final metadata) => metadata,
      DocumentPart(:final metadata) => metadata,
      _ => throw StateError('not a media part: ${part.type}'),
    };

const _mimeByModality = {
  'image': 'image/png',
  'audio': 'audio/wav',
  'video': 'video/mp4',
  'document': 'application/pdf',
};

void main() {
  group('Multimodal messages', () {
    test('parses user message with content array (text + image url)', () {
      final msg = UserMessage.fromJson({
        'id': 'user_multimodal',
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Check this out'},
          {
            'type': 'image',
            'source': {
              'type': 'url',
              'value': 'https://example.com/image.png',
              'mimeType': 'image/png',
            },
          },
        ],
      });

      final body = msg.messageContent;
      expect(body, isA<MultimodalContent>());
      final parts = (body as MultimodalContent).parts;
      expect(parts.length, 2);
      expect(parts[0], isA<TextPart>());
      expect((parts[0] as TextPart).text, 'Check this out');
      expect(parts[1], isA<ImagePart>());
      final source = (parts[1] as ImagePart).source;
      expect(source, isA<UrlSource>());
      expect((source as UrlSource).value, 'https://example.com/image.png');
    });

    test('parses image part with inline data source and metadata', () {
      final part = ContentPart.fromJson({
        'type': 'image',
        'source': {
          'type': 'data',
          'value': 'base64-value',
          'mimeType': 'image/png',
        },
        'metadata': {'detail': 'high'},
      });

      expect(part, isA<ImagePart>());
      final source = (part as ImagePart).source;
      expect(source, isA<DataSource>());
      expect((source as DataSource).mimeType, 'image/png');
      expect(part.metadata, {'detail': 'high'});
    });

    test('parses url source', () {
      final source = PartSource.fromJson({
        'type': 'url',
        'value': 'https://example.com/file.pdf',
      });

      expect(source, isA<UrlSource>());
      expect((source as UrlSource).value, 'https://example.com/file.pdf');
      expect(source.mimeType, isNull);
    });

    test('parses data source', () {
      final source = PartSource.fromJson({
        'type': 'data',
        'value': 'Zm9v',
        'mimeType': 'application/pdf',
      });

      expect(source, isA<DataSource>());
      expect((source as DataSource).mimeType, 'application/pdf');
    });

    test('rejects the legacy binary part, which protocol 1.0 retired', () {
      expect(
        () => ContentPart.fromJson({
          'type': 'binary',
          'mimeType': 'image/png',
          'data': 'base64',
        }),
        throwsA(isA<AGUIValidationError>()),
      );
    });

    test('parses a user message containing all modalities (order preserved)',
        () {
      final msg = UserMessage.fromJson({
        'id': 'user_all_modalities',
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'Process all inputs'},
          {
            'type': 'image',
            'source': {'type': 'url', 'value': 'https://example.com/image.png'},
          },
          {
            'type': 'audio',
            'source': {
              'type': 'data',
              'value': 'Zm9v',
              'mimeType': 'audio/wav'
            },
          },
          {
            'type': 'video',
            'source': {'type': 'url', 'value': 'https://example.com/video.mp4'},
          },
          {
            'type': 'document',
            'source': {
              'type': 'data',
              'value': 'YmFy',
              'mimeType': 'application/pdf',
            },
          },
        ],
      });

      final parts = (msg.messageContent as MultimodalContent).parts;
      expect(
        parts.map((p) => p.type).toList(),
        ['text', 'image', 'audio', 'video', 'document'],
      );
    });

    for (final modality in _mimeByModality.keys) {
      final mime = _mimeByModality[modality]!;
      group('$modality modality combinations', () {
        for (final withMetadata in [true, false]) {
          test('parses url source (metadata: $withMetadata)', () {
            final part = ContentPart.fromJson({
              'type': modality,
              'source': {
                'type': 'url',
                'value': 'https://example.com/$modality',
                'mimeType': mime,
              },
              if (withMetadata) 'metadata': {'providerHint': 'high'},
            });

            expect(part.type, modality);
            final source = _sourceOf(part);
            expect(source, isA<UrlSource>());
            expect(
                (source as UrlSource).value, 'https://example.com/$modality');
            if (withMetadata) {
              expect(_metadataOf(part), {'providerHint': 'high'});
            } else {
              expect(_metadataOf(part), isNull);
            }
          });

          test('parses data source (metadata: $withMetadata)', () {
            final part = ContentPart.fromJson({
              'type': modality,
              'source': {'type': 'data', 'value': 'Zm9v', 'mimeType': mime},
              if (withMetadata) 'metadata': {'providerHint': 'high'},
            });

            expect(part.type, modality);
            final source = _sourceOf(part);
            expect(source, isA<DataSource>());
            expect((source as DataSource).mimeType, mime);
            if (withMetadata) {
              expect(_metadataOf(part), {'providerHint': 'high'});
            } else {
              expect(_metadataOf(part), isNull);
            }
          });
        }

        test('accepts url source without mimeType', () {
          final part = ContentPart.fromJson({
            'type': modality,
            'source': {
              'type': 'url',
              'value': 'https://example.com/$modality/raw'
            },
          });

          final source = _sourceOf(part);
          expect(source, isA<UrlSource>());
          expect((source as UrlSource).mimeType, isNull);
        });

        test('rejects data source without mimeType', () {
          expect(
            () => ContentPart.fromJson({
              'type': modality,
              'source': {'type': 'data', 'value': 'Zm9v'},
            }),
            throwsA(isA<AGUIValidationError>()),
          );
        });

        test('rejects missing source', () {
          expect(
            () => ContentPart.fromJson({'type': modality}),
            throwsA(isA<AGUIValidationError>()),
          );
        });

        test('rejects invalid source discriminator', () {
          expect(
            () => ContentPart.fromJson({
              'type': modality,
              'source': {'type': 'blob', 'value': 'abc'},
            }),
            throwsA(isA<AGUIValidationError>()),
          );
        });
      });
    }
  });

  group('UserMessage content union', () {
    test('text constructor: content getter returns the text', () {
      final msg = UserMessage(id: 'u1', content: 'hello');
      expect(msg.content, 'hello');
      expect(msg.messageContent, isA<TextContent>());
      expect(msg.toJson()['content'], 'hello');
    });

    test('multimodal constructor: content getter is null', () {
      final msg = UserMessage.multimodal(
        id: 'u1',
        parts: [const TextPart('hi')],
      );
      expect(msg.content, isNull);
      expect(msg.messageContent, isA<MultimodalContent>());
      expect(msg.toJson()['content'], isA<List<dynamic>>());
    });

    test('fromJson with string content', () {
      final msg = UserMessage.fromJson({
        'id': 'u1',
        'role': 'user',
        'content': 'plain text',
      });
      expect(msg.messageContent, isA<TextContent>());
      expect(msg.content, 'plain text');
    });

    test('copyWith replaces messageContent', () {
      final original = UserMessage(id: 'u1', content: 'first');
      final updated = original.copyWith(
        messageContent: const TextContent('second'),
      );
      expect(updated.id, 'u1');
      expect(updated.content, 'second');
    });

    test('round-trip: text toJson is a String', () {
      const content = TextContent('hello');
      expect(content.toJson(), 'hello');
    });

    test('round-trip: multimodal toJson is a List of maps', () {
      const content = MultimodalContent([
        TextPart('hi'),
        ImagePart(
          source: UrlSource(value: 'https://example.com/i.png'),
        ),
      ]);
      final json = content.toJson();
      expect(json, isA<List<dynamic>>());
      expect((json as List).length, 2);
    });

    test('round-trip: fromJson(toJson(message)) reproduces structure', () {
      final msg = UserMessage.multimodal(
        id: 'u1',
        parts: [
          const TextPart('look'),
          const ImagePart(
            source: DataSource(value: 'Zm9v', mimeType: 'image/png'),
            metadata: {'detail': 'high'},
          ),
          const DocumentPart(
            source: FileSource(value: 'file-1', provider: 'openai'),
          ),
          const AudioPart(
            source: DataSource(value: 'YXVk', mimeType: 'audio/wav'),
            metadata: {'duration': '3s'},
          ),
          const VideoPart(
            source: UrlSource(value: 'https://example.com/video.mp4'),
          ),
          const DocumentPart(
            source: DataSource(value: 'ZG9j', mimeType: 'application/pdf'),
            metadata: {'pages': '5'},
          ),
        ],
      );

      final decoded = UserMessage.fromJson(msg.toJson());
      final parts = (decoded.messageContent as MultimodalContent).parts;
      expect(parts.map((p) => p.type).toList(),
          ['text', 'image', 'document', 'audio', 'video', 'document']);
      expect((parts[0] as TextPart).text, 'look');
      final imageSource = (parts[1] as ImagePart).source;
      expect((imageSource as DataSource).mimeType, 'image/png');
      expect((parts[1] as ImagePart).metadata, {'detail': 'high'});
      final fileSource = (parts[2] as DocumentPart).source;
      expect((fileSource as FileSource).provider, 'openai');
      final audioSource = (parts[3] as AudioPart).source;
      expect((audioSource as DataSource).mimeType, 'audio/wav');
      expect((parts[3] as AudioPart).metadata, {'duration': '3s'});
      final videoSource = (parts[4] as VideoPart).source;
      expect((videoSource as UrlSource).value, 'https://example.com/video.mp4');
      final docSource = (parts[5] as DocumentPart).source;
      expect((docSource as DataSource).mimeType, 'application/pdf');
      expect((parts[5] as DocumentPart).metadata, {'pages': '5'});
    });
  });

  group('MessageContent edge cases', () {
    test('empty parts list decodes to MultimodalContent', () {
      final content = MessageContent.fromJson(<dynamic>[]);
      expect(content, isA<MultimodalContent>());
      expect((content as MultimodalContent).parts, isEmpty);
    });

    test('null content is rejected', () {
      expect(
        () => MessageContent.fromJson(null),
        throwsA(isA<AGUIValidationError>()),
      );
    });

    test('absent content key is rejected via fromJson', () {
      expect(
        () => UserMessage.fromJson({'id': 'u1', 'role': 'user'}),
        throwsA(isA<AGUIValidationError>()),
      );
    });

    test('mixed valid + invalid part names the bad index', () {
      expect(
        () => MessageContent.fromJson([
          {'type': 'text', 'text': 'ok'},
          {'type': 'binary', 'mimeType': 'image/png'},
        ]),
        throwsA(
          isA<AGUIValidationError>().having(
            (e) => e.message,
            'message',
            contains('index 1'),
          ),
        ),
      );
    });

    test('unknown top-level part type is rejected', () {
      expect(
        () => ContentPart.fromJson({'type': 'hologram'}),
        throwsA(isA<AGUIValidationError>()),
      );
    });

    test('non-object part is rejected', () {
      expect(
        () => MessageContent.fromJson(['not-an-object']),
        throwsA(isA<AGUIValidationError>()),
      );
    });
  });

  group('copyWith can clear optional fields', () {
    test('ImagePart.copyWith(metadata: null) clears metadata', () {
      final part = ImagePart(
        source: UrlSource(value: 'https://example.com/img.png'),
        metadata: {'key': 'value'},
      );
      expect(part.copyWith(metadata: null).metadata, isNull);
    });

    test('ImagePart.copyWith() without metadata preserves it', () {
      final part = ImagePart(
        source: UrlSource(value: 'https://example.com/img.png'),
        metadata: {'key': 'value'},
      );
      expect(part.copyWith().metadata, {'key': 'value'});
    });

    test('AudioPart.copyWith(metadata: null) clears metadata', () {
      final part = AudioPart(
        source: DataSource(value: 'base64data', mimeType: 'audio/mp3'),
        metadata: {'duration': 42},
      );
      expect(part.copyWith(metadata: null).metadata, isNull);
    });

    test('VideoPart.copyWith(metadata: null) clears metadata', () {
      final part = VideoPart(
        source: DataSource(value: 'base64data', mimeType: 'video/mp4'),
        metadata: {'fps': 30},
      );
      expect(part.copyWith(metadata: null).metadata, isNull);
    });

    test('DocumentPart.copyWith(metadata: null) clears metadata', () {
      final part = DocumentPart(
        source: DataSource(value: 'base64data', mimeType: 'application/pdf'),
        metadata: {'pages': 10},
      );
      expect(part.copyWith(metadata: null).metadata, isNull);
    });

    test('UrlSource.copyWith(mimeType: null) clears mimeType', () {
      final src = UrlSource(
        value: 'https://example.com/img.png',
        mimeType: 'image/png',
      );
      expect(src.copyWith(mimeType: null).mimeType, isNull);
    });

    test('UrlSource.copyWith() without mimeType preserves it', () {
      final src = UrlSource(
        value: 'https://example.com/img.png',
        mimeType: 'image/png',
      );
      expect(src.copyWith().mimeType, 'image/png');
    });

    test('ImagePart.copyWith(id: null) clears id', () {
      const part = ImagePart(
        source: DataSource(value: 'base64data', mimeType: 'image/png'),
        id: 'img_1',
      );
      expect(part.copyWith(id: null).id, isNull);
    });

    test('ImagePart.copyWith() without id preserves it', () {
      const part = ImagePart(
        source: DataSource(value: 'base64data', mimeType: 'image/png'),
        id: 'img_1',
      );
      expect(part.copyWith().id, 'img_1');
    });
  });

  group('snake_case mime_type tolerance', () {
    test('data source accepts mime_type', () {
      final source = PartSource.fromJson({
        'type': 'data',
        'value': 'Zm9v',
        'mime_type': 'application/pdf',
      });
      expect((source as DataSource).mimeType, 'application/pdf');
    });

    test('url source accepts mime_type', () {
      final source = PartSource.fromJson({
        'type': 'url',
        'value': 'https://example.com/x',
        'mime_type': 'image/png',
      });
      expect((source as UrlSource).mimeType, 'image/png');
    });

    test('file source accepts mime_type', () {
      final source = PartSource.fromJson({
        'type': 'file',
        'value': 'file-abc',
        'mime_type': 'image/png',
      });
      expect((source as FileSource).mimeType, 'image/png');
    });
  });
}

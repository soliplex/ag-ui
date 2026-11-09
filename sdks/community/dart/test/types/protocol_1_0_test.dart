// Unit tests for the protocol 1.0 surface that the spec fixture corpus
// (test/spec/fixtures_test.dart) does not pin: copyWith on new fields,
// content projections, and decoder edge cases.
import 'package:ag_ui/ag_ui.dart';
import 'package:test/test.dart';

void main() {
  group('metadata and subagentRunId', () {
    test('event copyWith keeps, replaces and clears both fields', () {
      const event = TextMessageContentEvent(
        messageId: 'm1',
        delta: 'hi',
        metadata: {'k': 'v'},
        subagentRunId: 's1',
      );
      expect(event.toJson()['metadata'], {'k': 'v'});
      expect(event.toJson()['subagentRunId'], 's1');

      final kept = event.copyWith(delta: 'yo');
      expect(kept.metadata, {'k': 'v'});
      expect(kept.subagentRunId, 's1');

      final replaced =
          event.copyWith(metadata: {'k': 'w'}, subagentRunId: 's2');
      expect(replaced.metadata, {'k': 'w'});
      expect(replaced.subagentRunId, 's2');

      final cleared = event.copyWith(metadata: null, subagentRunId: null);
      expect(cleared.metadata, isNull);
      expect(cleared.subagentRunId, isNull);
      expect(cleared.toJson().containsKey('metadata'), isFalse);
      expect(cleared.toJson().containsKey('subagentRunId'), isFalse);
    });

    test('message copyWith keeps, replaces and clears both fields', () {
      const message = AssistantMessage(
        id: 'a1',
        content: 'hi',
        metadata: {'k': 'v'},
        subagentRunId: 's1',
      );
      final decoded = Message.fromJson(message.toJson()) as AssistantMessage;
      expect(decoded.metadata, {'k': 'v'});
      expect(decoded.subagentRunId, 's1');

      expect(message.copyWith().subagentRunId, 's1');
      final cleared = message.copyWith(metadata: null, subagentRunId: null);
      expect(cleared.metadata, isNull);
      expect(cleared.subagentRunId, isNull);
    });

    test('a null metadata is rejected on events and messages', () {
      expect(
        () => BaseEvent.fromJson({
          'type': 'TEXT_MESSAGE_END',
          'messageId': 'm1',
          'metadata': null,
        }),
        throwsA(isA<AGUIValidationError>()),
      );
      expect(
        () => Message.fromJson({
          'id': 'u1',
          'role': 'user',
          'content': 'hi',
          'metadata': null,
        }),
        throwsA(isA<AGUIValidationError>()),
      );
    });

    test('snake_case subagent_run_id is read', () {
      final event = BaseEvent.fromJson({
        'type': 'TEXT_MESSAGE_END',
        'messageId': 'm1',
        'subagent_run_id': 's9',
      });
      expect(event.subagentRunId, 's9');
    });
  });

  group('TextMessageStartEvent.role', () {
    test('absent role stays null and is omitted on the wire', () {
      final event = TextMessageStartEvent.fromJson({
        'type': 'TEXT_MESSAGE_START',
        'messageId': 'm1',
      });
      expect(event.role, isNull);
      expect(event.toJson().containsKey('role'), isFalse);
    });

    test('copyWith can set and clear the role', () {
      const event = TextMessageStartEvent(messageId: 'm1');
      final withRole = event.copyWith(role: TextMessageRole.user);
      expect(withRole.role, TextMessageRole.user);
      expect(withRole.copyWith().role, TextMessageRole.user);
      expect(withRole.copyWith(role: null).role, isNull);
    });
  });

  group('timestamps', () {
    test('a whole-valued double is accepted', () {
      final event = BaseEvent.fromJson({
        'type': 'TEXT_MESSAGE_END',
        'messageId': 'm1',
        'timestamp': 1700000000.0,
      });
      expect(event.timestamp, 1700000000);
    });

    test('a fractional timestamp is rejected rather than floored', () {
      expect(
        () => BaseEvent.fromJson({
          'type': 'TEXT_MESSAGE_END',
          'messageId': 'm1',
          'timestamp': 1.5,
        }),
        throwsA(isA<AGUIValidationError>()),
      );
    });

    test('the bound is 2^53 - 1', () {
      final ok = BaseEvent.fromJson({
        'type': 'TEXT_MESSAGE_END',
        'messageId': 'm1',
        'timestamp': 9007199254740991,
      });
      expect(ok.timestamp, 9007199254740991);
      expect(
        () => BaseEvent.fromJson({
          'type': 'TEXT_MESSAGE_END',
          'messageId': 'm1',
          'timestamp': 9007199254740992,
        }),
        throwsA(isA<AGUIValidationError>()),
      );
    });
  });

  group('JSON Patch validation', () {
    Map<String, dynamic> delta(List<Map<String, dynamic>> ops) =>
        {'type': 'STATE_DELTA', 'delta': ops};

    test('accepts every RFC 6902 operation', () {
      final event = BaseEvent.fromJson(delta([
        {'op': 'add', 'path': '/a', 'value': 1},
        {'op': 'remove', 'path': '/a'},
        {'op': 'replace', 'path': '/b~1c', 'value': null},
        {'op': 'move', 'from': '/b', 'path': '/c'},
        {'op': 'copy', 'from': '/c', 'path': '/d'},
        {'op': 'test', 'path': '', 'value': <String, dynamic>{}},
      ])) as StateDeltaEvent;
      expect(event.delta, hasLength(6));
    });

    for (final (name, op) in [
      ('an unknown op', {'op': 'merge', 'path': '/a'}),
      ('a path without a leading slash', {'op': 'remove', 'path': 'a'}),
      ('a bad tilde escape', {'op': 'remove', 'path': '/a~2'}),
      ('add without value', {'op': 'add', 'path': '/a'}),
      ('move without from', {'op': 'move', 'path': '/a'}),
    ]) {
      test('rejects $name', () {
        expect(
          () => BaseEvent.fromJson(delta([op])),
          throwsA(isA<AGUIValidationError>()),
        );
      });
    }
  });

  group('MessageContent', () {
    test('text content projects to itself', () {
      const content = TextContent('plain');
      expect(content.text, 'plain');
      expect(content.hasMedia, isFalse);
    });

    test('parts project to their joined text and report media', () {
      const content = MultimodalContent([
        TextPart('a'),
        ImagePart(source: UrlSource(value: 'https://x/y.png')),
        TextPart('b'),
      ]);
      expect(content.text, 'ab');
      expect(content.hasMedia, isTrue);
      expect(
        const MultimodalContent([TextPart('only')]).hasMedia,
        isFalse,
      );
    });

    test('the 0.x names are aliases of the 1.0 ones', () {
      // ignore: deprecated_member_use_from_same_package
      const InputContent part = TextInputContent('x');
      expect(part, isA<TextPart>());
    });
  });

  group('ToolMessage and ToolCallResultEvent content', () {
    test('ToolCallResultEvent.fromContent carries parts', () {
      const event = ToolCallResultEvent.fromContent(
        messageId: 'm1',
        toolCallId: 'c1',
        messageContent: MultimodalContent([TextPart('3 results')]),
      );
      expect(event.content, '3 results');
      expect(event.toJson()['content'], [
        {'type': 'text', 'text': '3 results'},
      ]);

      final decoded = BaseEvent.fromJson(event.toJson()) as ToolCallResultEvent;
      expect(decoded.messageContent, isA<MultimodalContent>());

      final swapped = event.copyWith(messageContent: const TextContent('x'));
      expect(swapped.toJson()['content'], 'x');
      expect(swapped.toolCallId, 'c1');
    });

    test('the string constructor still produces a string on the wire', () {
      final event = ToolCallResultEvent(
        messageId: 'm1',
        toolCallId: 'c1',
        content: 'ok',
      );
      expect(event.toJson()['content'], 'ok');

      final message = ToolMessage(id: 't1', content: 'ok', toolCallId: 'c1');
      expect(message.toJson()['content'], 'ok');
      expect(message.content, 'ok');
    });

    test('ToolMessage decodes a list of parts', () {
      final message = Message.fromJson({
        'id': 't1',
        'role': 'tool',
        'toolCallId': 'c1',
        'content': [
          {'type': 'text', 'text': 'see'},
          {
            'type': 'document',
            'source': {'type': 'file', 'value': 'file-1'},
          },
        ],
      }) as ToolMessage;
      expect(message.content, 'see');
      expect(message.messageContent.hasMedia, isTrue);
    });
  });

  group('RunFinishedEvent outcome and usage', () {
    test('copyWith keeps, replaces and clears outcome and usage', () {
      const event = RunFinishedEvent(
        threadId: 't',
        runId: 'r',
        outcome: RunFinishedSuccessOutcome(pendingToolCallIds: ['c1']),
        usage: [TokenUsage(model: 'm', inputTokens: 3, outputTokens: 4)],
      );
      final json = event.toJson();
      expect(json['outcome'], {
        'type': 'success',
        'pendingToolCallIds': ['c1'],
      });
      expect(json['usage'], [
        {'model': 'm', 'inputTokens': 3, 'outputTokens': 4},
      ]);

      expect(event.copyWith().outcome, isA<RunFinishedSuccessOutcome>());
      final cancelled =
          event.copyWith(outcome: const RunFinishedCancelledOutcome());
      expect(cancelled.toJson()['outcome'], {'type': 'cancelled'});
      expect(cancelled.usage, hasLength(1));

      final cleared = event.copyWith(outcome: null, usage: null);
      expect(cleared.toJson().containsKey('outcome'), isFalse);
      expect(cleared.toJson().containsKey('usage'), isFalse);
    });

    test('an interrupt outcome decodes its interrupts', () {
      final event = BaseEvent.fromJson({
        'type': 'RUN_FINISHED',
        'threadId': 't',
        'runId': 'r',
        'outcome': {
          'type': 'interrupt',
          'interrupts': [
            {'id': 'i1', 'reason': 'tool_approval', 'toolCallId': 'c1'},
          ],
        },
      }) as RunFinishedEvent;
      final outcome = event.outcome! as RunFinishedInterruptOutcome;
      expect(outcome.interrupts.single.toolCallId, 'c1');
    });

    test('RunErrorEvent tolerates a null usage', () {
      final event = BaseEvent.fromJson({
        'type': 'RUN_ERROR',
        'message': 'boom',
        'usage': null,
      }) as RunErrorEvent;
      expect(event.usage, isNull);
    });
  });

  group('RunAgentInput', () {
    test('toJson always writes tools and context', () {
      const input = RunAgentInput(threadId: 't', runId: 'r', messages: []);
      final json = input.toJson();
      expect(json['tools'], isEmpty);
      expect(json['context'], isEmpty);
      expect(json.containsKey('protocolVersion'), isFalse);
      expect(json.containsKey('resume'), isFalse);
    });

    test('absent tools and context decode as empty', () {
      final input = RunAgentInput.fromJson({
        'threadId': 't',
        'runId': 'r',
        'messages': <dynamic>[],
      });
      expect(input.tools, isEmpty);
      expect(input.context, isEmpty);
    });

    test('protocolVersion and resume round-trip and copyWith', () {
      const input = RunAgentInput(
        threadId: 't',
        runId: 'r',
        messages: [],
        protocolVersion: agUiProtocolVersion,
        resume: [
          ResumeEntry(
            interruptId: 'i1',
            status: ResumeStatus.resolved,
            payload: {'approved': true},
          ),
        ],
      );
      final decoded = RunAgentInput.fromJson(input.toJson());
      expect(decoded.protocolVersion, '1.0');
      expect(decoded.resume!.single.payload, {'approved': true});

      expect(input.copyWith().resume, hasLength(1));
      final cleared = input.copyWith(protocolVersion: null, resume: null);
      expect(cleared.protocolVersion, isNull);
      expect(cleared.resume, isNull);
    });
  });

  group('subagent events', () {
    test('SubagentStartedEvent.subagentRunId is non-null', () {
      final event = BaseEvent.fromJson({
        'type': 'SUBAGENT_STARTED',
        'subagentRunId': 's1',
        'name': 'researcher',
      }) as SubagentStartedEvent;
      final String id = event.subagentRunId;
      expect(id, 's1');
      expect(event.copyWith(name: 'writer').subagentRunId, 's1');
    });

    test('a subagent event without subagentRunId is rejected', () {
      expect(
        () => BaseEvent.fromJson({'type': 'SUBAGENT_ERROR', 'message': 'x'}),
        throwsA(isA<AGUIValidationError>()),
      );
    });

    test('SubagentFinishedEvent decodes a suspended outcome', () {
      final event = BaseEvent.fromJson({
        'type': 'SUBAGENT_FINISHED',
        'subagentRunId': 's1',
        'outcome': {
          'type': 'suspended',
          'interruptIds': ['i1'],
        },
      }) as SubagentFinishedEvent;
      expect(
        (event.outcome! as SubagentFinishedSuspendedOutcome).interruptIds,
        ['i1'],
      );
    });
  });
}

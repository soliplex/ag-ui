/// Runs the AG-UI 1.0 specification's fixture corpus (`spec/1.0/fixtures`)
/// through the Dart codec.
///
/// For every schema definition the SDK models, a `valid/` document must
/// decode and encode back to the same JSON (plus any [_wireDefaults] the SDK
/// writes), and an `invalid/` document must be rejected, unless [_tolerated]
/// says why this SDK accepts it. A definition the SDK does not model is
/// listed in [_unmodelled], so a fixture directory nobody maps fails the run
/// rather than shrinking the corpus silently.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ag_ui/ag_ui.dart';
import 'package:test/test.dart';

/// Decoders keyed by the schema definition each fixture directory is named
/// after. Each returns the encoded form of what it decoded.
final Map<String, Object? Function(Object?)> _decoders = {
  for (final name in _eventDefinitions)
    name: (json) => BaseEvent.fromJson(_object(json)).toJson(),
  'UserMessage': (json) => Message.fromJson(_object(json)).toJson(),
  'ToolMessage': (json) => Message.fromJson(_object(json)).toJson(),
  'Tool': (json) => Tool.fromJson(_object(json)).toJson(),
  'RunAgentInput': (json) => RunAgentInput.fromJson(_object(json)).toJson(),
  'FileSource': (json) => PartSource.fromJson(_object(json)).toJson(),
  'Interrupt': (json) => Interrupt.fromJson(_object(json)).toJson(),
  'ResumeEntry': (json) => ResumeEntry.fromJson(_object(json)).toJson(),
};

const _eventDefinitions = [
  'ActivityDeltaEvent',
  'ActivitySnapshotEvent',
  'CustomEvent',
  'MessagesSnapshotEvent',
  'RawEvent',
  'ReasoningEncryptedValueEvent',
  'ReasoningEndEvent',
  'ReasoningMessageChunkEvent',
  'ReasoningMessageContentEvent',
  'ReasoningMessageEndEvent',
  'ReasoningMessageStartEvent',
  'ReasoningStartEvent',
  'RunErrorEvent',
  'RunFinishedEvent',
  'RunStartedEvent',
  'StateDeltaEvent',
  'StateSnapshotEvent',
  'StepFinishedEvent',
  'StepStartedEvent',
  'SubagentErrorEvent',
  'SubagentFinishedEvent',
  'SubagentStartedEvent',
  'TextMessageChunkEvent',
  'TextMessageContentEvent',
  'TextMessageEndEvent',
  'TextMessageStartEvent',
  'ToolCallArgsEvent',
  'ToolCallChunkEvent',
  'ToolCallEndEvent',
  'ToolCallResultEvent',
  'ToolCallStartEvent',
];

/// Definitions with fixtures that this SDK deliberately does not model.
///
/// Capabilities are what an agent declares about itself on a separate
/// endpoint; this client does not fetch them yet. `SubagentInfo` appears
/// only inside them.
const Set<String> _unmodelled = {
  'AgentCapabilities',
  'ExecutionCapabilities',
  'MultiAgentCapabilities',
  'SubagentInfo',
};

/// Invalid fixtures this SDK accepts on purpose, keyed by
/// `<Definition>/<file>`, with the reason.
///
/// Each is a case where the specification lets a consumer recover rather
/// than fail, and the TypeScript client recovers too: it strips unknown
/// properties with a warning, and reads some whole-field nulls as absent.
const Map<String, String> _tolerated = {
  'FileSource/reference-record.json': _strips,
  'RunFinishedEvent/outcome-cancelled-carrying-interrupts.json': _strips,
  'RunFinishedEvent/outcome-interrupt-carrying-pending-tool-call-ids.json':
      _strips,
  'RunFinishedEvent/outcome-success-carrying-interrupts.json': _strips,
  'SubagentFinishedEvent/outcome-success-carrying-interrupt-ids.json': _strips,
  'TextMessageEndEvent/unknown-property.json': _strips,
  'TextMessageContentEvent/subagent-run-id-null.json': _nullIsAbsent,
  'TextMessageEndEvent/raw-event-null.json': _nullIsAbsent,
  'ToolCallChunkEvent/parent-message-id-null.json': _nullIsAbsent,
  'ToolCallStartEvent/parent-message-id-null.json': _nullIsAbsent,
  'ToolCallResultEvent/role-not-tool.json':
      'an unrecognised role reads as the only legal one, "tool"',
};

const _strips = 'an unknown property is dropped';
const _nullIsAbsent = 'a null on a field older than 1.0 reads as absent';

/// Adds the fields [definition]'s encoder writes even when the wire omitted
/// them, so a round trip can be compared with the document it came from.
Object? _wireDefaults(String definition, Object? json) {
  Map<String, dynamic> withLists(Map<String, dynamic> input) => {
        ...input,
        'tools': input['tools'] ?? <Object?>[],
        'context': input['context'] ?? <Object?>[],
      };
  if (json is! Map<String, dynamic>) return json;
  return switch (definition) {
    // A 0.x Python agent requires both lists, so the SDK always writes them.
    'RunAgentInput' => withLists(json),
    'RunStartedEvent' when json['input'] is Map<String, dynamic> => {
        ...json,
        'input': withLists(json['input'] as Map<String, dynamic>),
      },
    _ => json,
  };
}

Map<String, dynamic> _object(Object? json) {
  if (json is Map<String, dynamic>) return json;
  throw ArgumentError('expected a JSON object, got ${json.runtimeType}');
}

Directory _fixtureRoot() {
  var dir = Directory.current;
  while (true) {
    final candidate = Directory('${dir.path}/spec/1.0/fixtures');
    if (candidate.existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
          'spec/1.0/fixtures not found above ${Directory.current}');
    }
    dir = parent;
  }
}

void main() {
  final root = _fixtureRoot();
  final definitions = root
      .listSync()
      .whereType<Directory>()
      .map((d) => d.uri.pathSegments.where((s) => s.isNotEmpty).last)
      .toList()
    ..sort();

  test('every fixture directory is mapped or listed as unmodelled', () {
    final unmapped = definitions
        .where((d) => !_decoders.containsKey(d) && !_unmodelled.contains(d));
    expect(unmapped, isEmpty);
  });

  for (final definition in definitions) {
    final decode = _decoders[definition];
    if (decode == null) continue;
    group(definition, () {
      for (final kind in const ['valid', 'invalid']) {
        final dir = Directory('${root.path}/$definition/$kind');
        if (!dir.existsSync()) continue;
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .where((f) => !f.path.endsWith('.expect.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        for (final file in files) {
          final name = file.uri.pathSegments.last;
          final json = jsonDecode(file.readAsStringSync());
          final tolerated = _tolerated['$definition/$name'];
          if (kind == 'valid') {
            test('decodes and re-encodes $name', () {
              expect(decode(json), equals(_wireDefaults(definition, json)));
            });
          } else if (tolerated != null) {
            test('accepts $name: $tolerated', () {
              expect(() => decode(json), returnsNormally);
            });
          } else {
            test('rejects $name', () {
              expect(() => decode(json), throwsA(anything));
            });
          }
        }
      }
    });
  }
}

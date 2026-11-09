/// Context and run types for AG-UI protocol.
library;

import 'base.dart';
import 'message.dart';
import 'run.dart';
import 'tool.dart';

// `kUnsetSentinel` (from `base.dart`) is the shared sentinel for all
// `copyWith` methods in this file.

/// Additional context for the agent
class Context extends AGUIModel {
  final String description;
  final String value;

  const Context({
    required this.description,
    required this.value,
  });

  factory Context.fromJson(Map<String, dynamic> json) {
    return Context(
      description: JsonDecoder.requireField<String>(json, 'description'),
      value: JsonDecoder.requireField<String>(json, 'value'),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'description': description,
        'value': value,
      };

  @override
  Context copyWith({
    String? description,
    String? value,
  }) {
    return Context(
      description: description ?? this.description,
      value: value ?? this.value,
    );
  }
}

/// Input for running an agent.
///
/// The optional [parentRunId] mirrors the canonical TS/Python
/// `RunAgentInput.parentRunId` / `parent_run_id` field; it links the
/// run to a parent run in nested-run scenarios.
///
/// [tools] and [context] are optional on the wire since protocol 1.0, and
/// absent means empty. [toJson] still writes both, empty or not, because a
/// 0.x Python agent requires them.
class RunAgentInput extends AGUIModel {
  final String threadId;
  final String runId;

  /// The protocol version the client speaks, such as [agUiProtocolVersion].
  /// Left unset, it is omitted: a 0.x agent may reject a field it does not
  /// know.
  final String? protocolVersion;
  final String? parentRunId;
  final dynamic state;
  final List<Message> messages;
  final List<Tool> tools;
  final List<Context> context;
  final dynamic forwardedProps;

  /// Answers to the interrupts the previous run finished with.
  final List<ResumeEntry>? resume;

  const RunAgentInput({
    required this.threadId,
    required this.runId,
    this.protocolVersion,
    this.parentRunId,
    this.state,
    required this.messages,
    this.tools = const [],
    this.context = const [],
    this.forwardedProps,
    this.resume,
  });

  factory RunAgentInput.fromJson(Map<String, dynamic> json) {
    return RunAgentInput(
      threadId: JsonDecoder.requireEitherField<String>(
        json,
        'threadId',
        'thread_id',
      ),
      runId: JsonDecoder.requireEitherField<String>(
        json,
        'runId',
        'run_id',
      ),
      protocolVersion:
          JsonDecoder.optionalStrictField<String>(json, 'protocolVersion'),
      parentRunId: JsonDecoder.optionalEitherField<String>(
        json,
        'parentRunId',
        'parent_run_id',
      ),
      state: json['state'],
      messages: () {
        final raw = JsonDecoder.requireListField<Map<String, dynamic>>(
          json,
          'messages',
        );
        final out = <Message>[];
        for (var i = 0; i < raw.length; i++) {
          try {
            out.add(Message.fromJson(raw[i]));
          } on AGUIValidationError catch (e) {
            // Drop json: — the inner payload may carry encryptedValue or tool
            // arguments. Preserve cause: when the inner error already cleared
            // its own json: (e.json == null), meaning the inner factory was
            // cipher-aware and the cause chain is safe to forward.
            throw AGUIValidationError(
              message: e.message,
              field: 'messages[$i].${e.field ?? 'unknown'}',
              value: e.value,
              cause: e.json == null ? e : null,
            );
          } catch (e) {
            throw AGUIValidationError(
              message: 'Failed to decode message at index $i: $e',
              field: 'messages[$i]',
              cause: e,
            );
          }
        }
        return out;
      }(),
      tools: () {
        final raw = JsonDecoder.optionalListField<Map<String, dynamic>>(
              json,
              'tools',
            ) ??
            const [];
        final out = <Tool>[];
        for (var i = 0; i < raw.length; i++) {
          try {
            out.add(Tool.fromJson(raw[i]));
          } on AGUIValidationError catch (e) {
            // Drop json: — tool arguments may be sensitive. Preserve cause:
            // when e.json == null (inner factory already scrubbed it).
            throw AGUIValidationError(
              message: e.message,
              field: 'tools[$i].${e.field ?? 'unknown'}',
              value: e.value,
              cause: e.json == null ? e : null,
            );
          } catch (e) {
            throw AGUIValidationError(
              message: 'Failed to decode tool at index $i: $e',
              field: 'tools[$i]',
              cause: e,
            );
          }
        }
        return out;
      }(),
      context: () {
        final raw = JsonDecoder.optionalListField<Map<String, dynamic>>(
              json,
              'context',
            ) ??
            const [];
        final out = <Context>[];
        for (var i = 0; i < raw.length; i++) {
          try {
            out.add(Context.fromJson(raw[i]));
          } on AGUIValidationError catch (e) {
            // Drop json: — context values may carry sensitive data. Preserve
            // cause: when e.json == null (inner factory already scrubbed it).
            throw AGUIValidationError(
              message: e.message,
              field: 'context[$i].${e.field ?? 'unknown'}',
              value: e.value,
              cause: e.json == null ? e : null,
            );
          } catch (e) {
            throw AGUIValidationError(
              message: 'Failed to decode context at index $i: $e',
              field: 'context[$i]',
              cause: e,
            );
          }
        }
        return out;
      }(),
      // `forwardedProps` is intentionally `dynamic` (any JSON shape),
      // so the inline KEY-presence chain is preferred over
      // `optionalEitherField<T>` (which requires a concrete `T`). Behavior
      // matches the helper: `camelKey` wins when the key is present (even
      // when its value is explicitly `null`); `snake_case` is consulted
      // ONLY when camelCase is entirely absent.
      forwardedProps: json.containsKey('forwardedProps')
          ? json['forwardedProps']
          : json['forwarded_props'],
      resume: JsonDecoder.optionalObjectList(
        json,
        'resume',
        ResumeEntry.fromJson,
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'threadId': threadId,
        'runId': runId,
        if (protocolVersion != null) 'protocolVersion': protocolVersion,
        if (parentRunId != null) 'parentRunId': parentRunId,
        if (state != null) 'state': state,
        'messages': messages.map((m) => m.toJson()).toList(),
        'tools': tools.map((t) => t.toJson()).toList(),
        'context': context.map((c) => c.toJson()).toList(),
        if (forwardedProps != null) 'forwardedProps': forwardedProps,
        if (resume != null) 'resume': resume!.map((r) => r.toJson()).toList(),
      };

  // `parentRunId`, `state`, and `forwardedProps` are nullable —
  // sentinel lets callers clear them explicitly via `copyWith(field: null)`.
  // Mirrors the message-class sentinel in lib/src/types/message.dart.
  @override
  RunAgentInput copyWith({
    String? threadId,
    String? runId,
    Object? protocolVersion = kUnsetSentinel,
    Object? parentRunId = kUnsetSentinel,
    Object? state = kUnsetSentinel,
    List<Message>? messages,
    List<Tool>? tools,
    List<Context>? context,
    Object? forwardedProps = kUnsetSentinel,
    Object? resume = kUnsetSentinel,
  }) {
    return RunAgentInput(
      threadId: threadId ?? this.threadId,
      runId: runId ?? this.runId,
      protocolVersion: identical(protocolVersion, kUnsetSentinel)
          ? this.protocolVersion
          : protocolVersion as String?,
      parentRunId: identical(parentRunId, kUnsetSentinel)
          ? this.parentRunId
          : parentRunId as String?,
      state: identical(state, kUnsetSentinel) ? this.state : state,
      messages: messages ?? this.messages,
      tools: tools ?? this.tools,
      context: context ?? this.context,
      forwardedProps: identical(forwardedProps, kUnsetSentinel)
          ? this.forwardedProps
          : forwardedProps,
      resume: identical(resume, kUnsetSentinel)
          ? this.resume
          : resume as List<ResumeEntry>?,
    );
  }
}

/// Represents a run in the AG-UI protocol
class Run extends AGUIModel {
  final String threadId;
  final String runId;
  final dynamic result;

  const Run({
    required this.threadId,
    required this.runId,
    this.result,
  });

  factory Run.fromJson(Map<String, dynamic> json) {
    return Run(
      threadId: JsonDecoder.requireEitherField<String>(
        json,
        'threadId',
        'thread_id',
      ),
      runId: JsonDecoder.requireEitherField<String>(
        json,
        'runId',
        'run_id',
      ),
      result: json['result'],
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'threadId': threadId,
        'runId': runId,
        if (result != null) 'result': result,
      };

  // `result` is nullable — sentinel for explicit-clear semantics.
  @override
  Run copyWith({
    String? threadId,
    String? runId,
    Object? result = kUnsetSentinel,
  }) {
    return Run(
      threadId: threadId ?? this.threadId,
      runId: runId ?? this.runId,
      result: identical(result, kUnsetSentinel) ? this.result : result,
    );
  }
}

/// Type alias for state (can be any type)
typedef State = dynamic;

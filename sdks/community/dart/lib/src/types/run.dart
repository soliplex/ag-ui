/// Run-level types that protocol 1.0 introduced: token usage, interrupts and
/// resumption, and the outcomes a run or a subagent run finishes with.
///
/// Every field here is new in 1.0, so no older producer writes an explicit
/// `null` for one; decoding treats such a `null` as malformed, as the
/// specification does.
library;

import 'base.dart';

/// The AG-UI protocol version this SDK speaks, for
/// `RunAgentInput.protocolVersion`. A producer declares its own on
/// `RUN_STARTED.protocolVersion`.
const String agUiProtocolVersion = '1.0';

/// Resolves a `copyWith` argument: [kUnsetSentinel] keeps [current].
T _pick<T>(Object? value, T current) =>
    identical(value, kUnsetSentinel) ? current : value as T;

/// Decodes a required list of strings, naming the failing index.
List<String> _strings(Map<String, dynamic> json, String field) =>
    JsonDecoder.requireListField<String>(json, field).toList();

/// Token counts a model reported for part of a run.
///
/// A run may report several, one per model or provider it called. Every
/// count is a non-negative integer.
class TokenUsage extends AGUIModel {
  final String? provider;
  final String? model;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final int? reasoningTokens;
  final int? cachedInputTokens;
  final int? cacheWriteInputTokens;

  const TokenUsage({
    this.provider,
    this.model,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.reasoningTokens,
    this.cachedInputTokens,
    this.cacheWriteInputTokens,
  });

  factory TokenUsage.fromJson(Map<String, dynamic> json) {
    // `provider` and the three detail counts tolerate a `null`, as the
    // TypeScript client's compatibility boundary does: early 1.0 Python
    // producers wrote one.
    int? count(String field, {bool nullable = false}) =>
        JsonDecoder.optionalSafeInteger(
          json,
          field,
          minimum: 0,
          nullable: nullable,
        );
    return TokenUsage(
      provider: JsonDecoder.optionalField<String>(json, 'provider'),
      model: JsonDecoder.optionalStrictField<String>(json, 'model'),
      inputTokens: count('inputTokens'),
      outputTokens: count('outputTokens'),
      totalTokens: count('totalTokens'),
      reasoningTokens: count('reasoningTokens', nullable: true),
      cachedInputTokens: count('cachedInputTokens', nullable: true),
      cacheWriteInputTokens: count('cacheWriteInputTokens', nullable: true),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        if (provider != null) 'provider': provider,
        if (model != null) 'model': model,
        if (inputTokens != null) 'inputTokens': inputTokens,
        if (outputTokens != null) 'outputTokens': outputTokens,
        if (totalTokens != null) 'totalTokens': totalTokens,
        if (reasoningTokens != null) 'reasoningTokens': reasoningTokens,
        if (cachedInputTokens != null) 'cachedInputTokens': cachedInputTokens,
        if (cacheWriteInputTokens != null)
          'cacheWriteInputTokens': cacheWriteInputTokens,
      };

  @override
  TokenUsage copyWith({
    Object? provider = kUnsetSentinel,
    Object? model = kUnsetSentinel,
    Object? inputTokens = kUnsetSentinel,
    Object? outputTokens = kUnsetSentinel,
    Object? totalTokens = kUnsetSentinel,
    Object? reasoningTokens = kUnsetSentinel,
    Object? cachedInputTokens = kUnsetSentinel,
    Object? cacheWriteInputTokens = kUnsetSentinel,
  }) =>
      TokenUsage(
        provider: _pick(provider, this.provider),
        model: _pick(model, this.model),
        inputTokens: _pick(inputTokens, this.inputTokens),
        outputTokens: _pick(outputTokens, this.outputTokens),
        totalTokens: _pick(totalTokens, this.totalTokens),
        reasoningTokens: _pick(reasoningTokens, this.reasoningTokens),
        cachedInputTokens: _pick(cachedInputTokens, this.cachedInputTokens),
        cacheWriteInputTokens:
            _pick(cacheWriteInputTokens, this.cacheWriteInputTokens),
      );
}

/// A request, raised by a run, for input the run cannot continue without:
/// an approval, a choice, a value.
///
/// A run that raises interrupts finishes with a [RunFinishedInterruptOutcome]
/// listing them; the client answers each with a [ResumeEntry] on the next
/// `RunAgentInput`.
class Interrupt extends AGUIModel {
  /// Identifies the interrupt; a [ResumeEntry] answers it by this id.
  final String id;

  /// Why the run stopped, as a machine-readable reason such as
  /// `tool_approval`.
  final String reason;

  /// A message for the person who will answer.
  final String? message;

  /// The tool call the interrupt is about, when it is about one.
  final String? toolCallId;

  /// A JSON Schema the answer's `payload` should satisfy.
  final Map<String, dynamic>? responseSchema;

  /// When the interrupt stops accepting an answer, as an RFC 3339 timestamp.
  final String? expiresAt;

  final Map<String, dynamic>? metadata;

  /// The subagent run that raised the interrupt, when one did.
  final String? subagentRunId;

  const Interrupt({
    required this.id,
    required this.reason,
    this.message,
    this.toolCallId,
    this.responseSchema,
    this.expiresAt,
    this.metadata,
    this.subagentRunId,
  });

  factory Interrupt.fromJson(Map<String, dynamic> json) => Interrupt(
        id: JsonDecoder.requireField<String>(json, 'id'),
        reason: JsonDecoder.requireField<String>(json, 'reason'),
        message: JsonDecoder.optionalStrictField<String>(json, 'message'),
        toolCallId: JsonDecoder.optionalStrictField<String>(json, 'toolCallId'),
        responseSchema: JsonDecoder.optionalStrictField<Map<String, dynamic>>(
          json,
          'responseSchema',
        ),
        expiresAt: JsonDecoder.optionalStrictField<String>(json, 'expiresAt'),
        metadata: JsonDecoder.optionalMetadata(json, 'metadata'),
        subagentRunId: JsonDecoder.optionalField<String>(json, 'subagentRunId'),
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'reason': reason,
        if (message != null) 'message': message,
        if (toolCallId != null) 'toolCallId': toolCallId,
        if (responseSchema != null) 'responseSchema': responseSchema,
        if (expiresAt != null) 'expiresAt': expiresAt,
        if (metadata != null) 'metadata': metadata,
        if (subagentRunId != null) 'subagentRunId': subagentRunId,
      };

  @override
  Interrupt copyWith({
    String? id,
    String? reason,
    Object? message = kUnsetSentinel,
    Object? toolCallId = kUnsetSentinel,
    Object? responseSchema = kUnsetSentinel,
    Object? expiresAt = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
    Object? subagentRunId = kUnsetSentinel,
  }) =>
      Interrupt(
        id: id ?? this.id,
        reason: reason ?? this.reason,
        message: _pick(message, this.message),
        toolCallId: _pick(toolCallId, this.toolCallId),
        responseSchema: _pick(responseSchema, this.responseSchema),
        expiresAt: _pick(expiresAt, this.expiresAt),
        metadata: _pick(metadata, this.metadata),
        subagentRunId: _pick(subagentRunId, this.subagentRunId),
      );
}

/// How a [ResumeEntry] answers its interrupt.
enum ResumeStatus {
  resolved('resolved'),
  cancelled('cancelled');

  final String value;
  const ResumeStatus(this.value);

  static ResumeStatus fromString(String value) => switch (value) {
        'resolved' => resolved,
        'cancelled' => cancelled,
        _ => throw AGUIValidationError(
            message: 'Invalid resume status: $value',
            field: 'status',
            value: value,
          ),
      };
}

/// The client's answer to one [Interrupt], sent on `RunAgentInput.resume`.
class ResumeEntry extends AGUIModel {
  /// The [Interrupt.id] this answers.
  final String interruptId;

  final ResumeStatus status;

  /// The answer itself, any JSON; for a resolved interrupt it should satisfy
  /// the interrupt's [Interrupt.responseSchema].
  final Object? payload;

  final Map<String, dynamic>? metadata;

  const ResumeEntry({
    required this.interruptId,
    required this.status,
    this.payload,
    this.metadata,
  });

  factory ResumeEntry.fromJson(Map<String, dynamic> json) => ResumeEntry(
        interruptId: JsonDecoder.requireField<String>(json, 'interruptId'),
        status: ResumeStatus.fromString(
          JsonDecoder.requireField<String>(json, 'status'),
        ),
        payload: json['payload'],
        metadata: JsonDecoder.optionalMetadata(json, 'metadata'),
      );

  @override
  Map<String, dynamic> toJson() => {
        'interruptId': interruptId,
        'status': status.value,
        if (payload != null) 'payload': payload,
        if (metadata != null) 'metadata': metadata,
      };

  @override
  ResumeEntry copyWith({
    String? interruptId,
    ResumeStatus? status,
    Object? payload = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
  }) =>
      ResumeEntry(
        interruptId: interruptId ?? this.interruptId,
        status: status ?? this.status,
        payload: _pick(payload, this.payload),
        metadata: _pick(metadata, this.metadata),
      );
}

/// How a run finished, carried on `RUN_FINISHED.outcome`.
///
/// [RunFinishedSuccessOutcome], [RunFinishedInterruptOutcome] or
/// [RunFinishedCancelledOutcome]. An absent outcome predates 1.0 and means
/// success.
sealed class RunFinishedOutcome extends AGUIModel with TypeDiscriminator {
  const RunFinishedOutcome();

  factory RunFinishedOutcome.fromJson(Map<String, dynamic> json) {
    final type = JsonDecoder.requireField<String>(json, 'type');
    return switch (type) {
      'success' => RunFinishedSuccessOutcome(
          pendingToolCallIds: json['pendingToolCallIds'] == null
              ? null
              : _strings(json, 'pendingToolCallIds'),
        ),
      'interrupt' => RunFinishedInterruptOutcome(
          interrupts: () {
            final interrupts = JsonDecoder.requireObjectList(
              json,
              'interrupts',
              Interrupt.fromJson,
            );
            if (interrupts.isEmpty) {
              throw AGUIValidationError(
                message: 'An interrupt outcome needs at least one interrupt',
                field: 'interrupts',
              );
            }
            return interrupts;
          }(),
        ),
      'cancelled' => const RunFinishedCancelledOutcome(),
      _ => throw AGUIValidationError(
          message: 'Invalid run outcome type: $type',
          field: 'type',
          value: type,
        ),
    };
  }

  @override
  RunFinishedOutcome copyWith();
}

/// The run did what it was asked.
class RunFinishedSuccessOutcome extends RunFinishedOutcome {
  /// Tool calls the run issued and left for the client to execute; their
  /// results go back on the next run.
  final List<String>? pendingToolCallIds;

  const RunFinishedSuccessOutcome({this.pendingToolCallIds});

  @override
  String get type => 'success';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (pendingToolCallIds != null)
          'pendingToolCallIds': pendingToolCallIds,
      };

  @override
  RunFinishedSuccessOutcome copyWith({
    Object? pendingToolCallIds = kUnsetSentinel,
  }) =>
      RunFinishedSuccessOutcome(
        pendingToolCallIds: _pick(pendingToolCallIds, this.pendingToolCallIds),
      );
}

/// The run stopped to wait for answers to [interrupts].
class RunFinishedInterruptOutcome extends RunFinishedOutcome {
  /// What the run is waiting for; never empty.
  final List<Interrupt> interrupts;

  const RunFinishedInterruptOutcome({required this.interrupts});

  @override
  String get type => 'interrupt';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'interrupts': interrupts.map((i) => i.toJson()).toList(),
      };

  @override
  RunFinishedInterruptOutcome copyWith({List<Interrupt>? interrupts}) =>
      RunFinishedInterruptOutcome(interrupts: interrupts ?? this.interrupts);
}

/// The run was cancelled before it finished.
class RunFinishedCancelledOutcome extends RunFinishedOutcome {
  const RunFinishedCancelledOutcome();

  @override
  String get type => 'cancelled';

  @override
  Map<String, dynamic> toJson() => {'type': type};

  @override
  RunFinishedCancelledOutcome copyWith() => this;
}

/// How a subagent run finished, carried on `SUBAGENT_FINISHED.outcome`.
sealed class SubagentFinishedOutcome extends AGUIModel with TypeDiscriminator {
  const SubagentFinishedOutcome();

  factory SubagentFinishedOutcome.fromJson(Map<String, dynamic> json) {
    final type = JsonDecoder.requireField<String>(json, 'type');
    return switch (type) {
      'success' => const SubagentFinishedSuccessOutcome(),
      'suspended' => SubagentFinishedSuspendedOutcome(
          interruptIds: json['interruptIds'] == null
              ? null
              : _strings(json, 'interruptIds'),
        ),
      _ => throw AGUIValidationError(
          message: 'Invalid subagent outcome type: $type',
          field: 'type',
          value: type,
        ),
    };
  }

  @override
  SubagentFinishedOutcome copyWith();
}

/// The subagent run did what it was asked.
class SubagentFinishedSuccessOutcome extends SubagentFinishedOutcome {
  const SubagentFinishedSuccessOutcome();

  @override
  String get type => 'success';

  @override
  Map<String, dynamic> toJson() => {'type': type};

  @override
  SubagentFinishedSuccessOutcome copyWith() => this;
}

/// The subagent run stopped on interrupts the parent run surfaces.
class SubagentFinishedSuspendedOutcome extends SubagentFinishedOutcome {
  /// The [Interrupt.id]s it is waiting on.
  final List<String>? interruptIds;

  const SubagentFinishedSuspendedOutcome({this.interruptIds});

  @override
  String get type => 'suspended';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (interruptIds != null) 'interruptIds': interruptIds,
      };

  @override
  SubagentFinishedSuspendedOutcome copyWith({
    Object? interruptIds = kUnsetSentinel,
  }) =>
      SubagentFinishedSuspendedOutcome(
        interruptIds: _pick(interruptIds, this.interruptIds),
      );
}

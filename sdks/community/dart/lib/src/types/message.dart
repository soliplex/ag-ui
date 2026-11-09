/// Message types for AG-UI protocol.
///
/// This library defines the message types used in agent-user conversations,
/// including user, assistant, system, tool, developer, activity, and
/// reasoning messages.
library;

import 'base.dart';
import 'tool.dart';

// `kUnsetSentinel` (from `base.dart`) is the shared sentinel for all
// `copyWith` methods in this file. The pattern lets callers distinguish
// "argument omitted" (preserve current value via `?? this.field`) from
// "argument explicitly null" (clear the field). Compared with `identical(...)`.

/// Role types for messages in the AG-UI protocol.
///
/// Mirrors the canonical TypeScript and Python `Message` discriminated
/// unions (see `sdks/typescript/packages/core/src/types.ts` and
/// `sdks/python/ag_ui/core/types.py`). The `activity` and `reasoning`
/// values exist so `MESSAGES_SNAPSHOT` payloads carrying those message
/// shapes decode in Dart with the same schema as the other SDKs.
enum MessageRole {
  developer('developer'),
  system('system'),
  assistant('assistant'),
  user('user'),
  tool('tool'),

  /// Wire spelling is `'activity'` (lowercase, single word) — canonical
  /// across the AG-UI protocol (TS `Literal["activity"]`, Python
  /// `Literal["activity"]`). The Dart symbol matches; this enum value
  /// pins the wire constant for [MessageRole.fromString] dispatch into
  /// [ActivityMessage]. Mirrors the wire-spelling-pinning style used by
  /// [ReasoningEncryptedValueSubtype.toolCall] (where the spelling
  /// difference is more consequential).
  ///
  /// **Cipher asymmetry:** unlike [reasoning], `activity` messages never
  /// carry cipher data in the structured field — [ActivityMessage.fromJson]
  /// silently strips any wire-level `encryptedValue`. See [ActivityMessage]
  /// class-doc for the rationale.
  activity('activity'),

  /// Wire spelling is `'reasoning'` (lowercase, single word) — canonical
  /// across the AG-UI protocol. The Dart symbol matches; this enum value
  /// pins the wire constant for [MessageRole.fromString] dispatch into
  /// [ReasoningMessage].
  reasoning('reasoning');

  final String value;
  const MessageRole(this.value);

  /// Parses [value] into a [MessageRole].
  ///
  /// Unlike `TextMessageRole.fromString` / `ReasoningMessageRole.fromString`
  /// (which throw `ArgumentError` and are absorbed at the event-factory
  /// level for forward-compat), this enum throws [AGUIValidationError]
  /// directly — the value is the discriminator that selects which
  /// [Message] subtype's `fromJson` to dispatch to, so an unknown role
  /// has no safe default. Mis-tagging a `MESSAGES_SNAPSHOT` payload
  /// would corrupt the snapshot rather than just lose one field.
  ///
  /// Through the public [EventDecoder] pipeline, this surfaces as
  /// `DecodingError(field: 'role')`. Direct callers of `Message.fromJson`
  /// see `AGUIValidationError` directly. See `dart-enum-parsing-safety.md`
  /// for the closed-vs-open enum rationale.
  static final Map<String, MessageRole> _byValue = Map.unmodifiable({
    for (final r in MessageRole.values) r.value: r,
  });

  static MessageRole fromString(String value) {
    return _byValue[value] ??
        (throw AGUIValidationError(
          message: 'Invalid message role: $value',
          field: 'role',
          value: value,
        ));
  }
}

/// Base message class for all message types.
///
/// Messages represent the fundamental units of conversation in the AG-UI protocol.
/// Each message has a role, optional content, and may include additional metadata.
///
/// Use the [Message.fromJson] factory to deserialize messages from JSON.
///
/// Known parity gap with the canonical TS/Python SDKs: the canonical
/// `BaseMessageSchema.id` is `z.string()` (non-nullable). Dart keeps
/// `id` typed `String?` for legacy reasons but every concrete subtype
/// constructor declares it `required`, so a constructed in-memory
/// instance is null-safe by convention. A future major version may
/// tighten the type. See CHANGELOG → "Known parity gaps".
sealed class Message extends AGUIModel with TypeDiscriminator {
  final String? id;
  final MessageRole role;
  final String? content;
  final String? name;

  /// Opaque cipher payload preserved verbatim across proxy hops.
  ///
  /// Mirrors the canonical TS `BaseMessageSchema.encryptedValue:
  /// z.string().optional()` and Python `BaseMessage.encrypted_value:
  /// Optional[str]` — every concrete subtype that extends `BaseMessage`
  /// (Developer/System/Assistant/User/Tool) inherits this field. The
  /// canonical `ActivityMessage` and `ReasoningMessage` are NOT
  /// `BaseMessage` extensions; in this Dart sealed-class hierarchy they
  /// inherit the field too but their `fromJson` / `toJson` ignore it
  /// (`ActivityMessage`) or inherit it through the sealed parent without
  /// re-declaring locally (`ReasoningMessage` passes it via
  /// `super.encryptedValue` — there is no shadowing field on that subtype).
  ///
  /// Wire dual-key: factories read both `encryptedValue` (TS-canonical)
  /// and `encrypted_value` (Python-canonical) via
  /// [JsonDecoder.optionalEitherField]. `toJson` emits the camelCase
  /// spelling.
  final String? encryptedValue;

  /// Open, application-defined data about this message. Never interpreted.
  final Map<String, dynamic>? metadata;

  /// The subagent run that produced this message, when one did.
  final String? subagentRunId;

  const Message({
    this.id,
    required this.role,
    this.content,
    this.name,
    this.encryptedValue,
    this.metadata,
    this.subagentRunId,
  });

  @override
  String get type => role.value;

  /// Factory constructor to create specific message types from JSON
  factory Message.fromJson(Map<String, dynamic> json) {
    final roleStr = JsonDecoder.requireField<String>(json, 'role');
    final MessageRole role;
    try {
      role = MessageRole.fromString(roleStr);
    } on AGUIValidationError catch (e) {
      // Drop json: — the message map may carry encryptedValue. Preserve
      // cause: because MessageRole.fromString errors do not embed raw JSON
      // (e.json == null), so the cause chain is safe to forward.
      throw AGUIValidationError(
        message: e.message,
        field: e.field,
        value: e.value,
        cause: e,
      );
    }

    // `MessageRole.fromString` deliberately throws on unknown values rather
    // than falling back to a default — unlike `TextMessageRole.fromString`
    // and `ReasoningMessageRole.fromString`, which absorb `ArgumentError` for
    // forward-compat. The role is the *dispatch discriminator*: an unknown role
    // has no safe default subtype. Changing this to a fallback would silently
    // mis-tag a MESSAGES_SNAPSHOT message, corrupting the list instead of
    // surfacing the wire violation at the decoder boundary.
    switch (role) {
      case MessageRole.developer:
        return DeveloperMessage.fromJson(json);
      case MessageRole.system:
        return SystemMessage.fromJson(json);
      case MessageRole.assistant:
        return AssistantMessage.fromJson(json);
      case MessageRole.user:
        return UserMessage.fromJson(json);
      case MessageRole.tool:
        return ToolMessage.fromJson(json);
      case MessageRole.activity:
        return ActivityMessage.fromJson(json);
      case MessageRole.reasoning:
        return ReasoningMessage.fromJson(json);
      // No `default` clause — exhaustive switch on the [MessageRole] enum
      // (analyzer-enforced). A new MessageRole value will produce a compile
      // error here, which is the desired outcome rather than a runtime
      // fall-through.
    }
  }

  @override
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'role': role.value,
        if (content != null) 'content': content,
        if (name != null) 'name': name,
        if (encryptedValue != null) 'encryptedValue': encryptedValue,
        ..._attribution(this),
      };
}

/// The `metadata` and `subagentRunId` every message can carry, in wire form.
Map<String, dynamic> _attribution(Message m) => {
      if (m.metadata != null) 'metadata': m.metadata,
      if (m.subagentRunId != null) 'subagentRunId': m.subagentRunId,
    };

/// Reads `metadata`; a `null` one is rejected, as for events.
Map<String, dynamic>? _readMetadata(Map<String, dynamic> json) =>
    JsonDecoder.optionalMetadata(json, 'metadata');

/// Reads `subagentRunId` (or `subagent_run_id`); a `null` reads as absent.
String? _readSubagentRunId(Map<String, dynamic> json) =>
    JsonDecoder.optionalEitherField<String>(
      json,
      'subagentRunId',
      'subagent_run_id',
    );

/// Resolves a `copyWith` argument: [kUnsetSentinel] keeps [current].
T _pick<T>(Object? value, T current) =>
    identical(value, kUnsetSentinel) ? current : value as T;

/// Developer message with required content.
///
/// Used for system-level or developer-facing messages in the conversation.
final class DeveloperMessage extends Message {
  @override
  final String content;

  const DeveloperMessage({
    required super.id,
    required this.content,
    super.name,
    super.encryptedValue,
    super.metadata,
    super.subagentRunId,
  }) : super(role: MessageRole.developer);

  factory DeveloperMessage.fromJson(Map<String, dynamic> json) {
    return DeveloperMessage(
      id: JsonDecoder.requireField<String>(json, 'id'),
      content: JsonDecoder.requireField<String>(json, 'content'),
      name: JsonDecoder.optionalField<String>(json, 'name'),
      encryptedValue: JsonDecoder.optionalEitherField<String>(
        json,
        'encryptedValue',
        'encrypted_value',
      ),
      metadata: _readMetadata(json),
      subagentRunId: _readSubagentRunId(json),
    );
  }

  // Emit `content` unconditionally — it is constructor-required and non-null
  // on this subtype. The parent's conditional `if (content != null) 'content'`
  // would also work by construction, but emitting it here makes the contract
  // explicit and independent of the parent implementation.
  @override
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'role': role.value,
        'content': content,
        if (name != null) 'name': name,
        if (encryptedValue != null) 'encryptedValue': encryptedValue,
        ..._attribution(this),
      };

  // `name` and `encryptedValue` are nullable on the parent — use the
  // sentinel so callers can clear either explicitly. See [kUnsetSentinel].
  @override
  DeveloperMessage copyWith({
    String? id,
    String? content,
    Object? name = kUnsetSentinel,
    Object? encryptedValue = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
    Object? subagentRunId = kUnsetSentinel,
  }) {
    return DeveloperMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      name: identical(name, kUnsetSentinel) ? this.name : name as String?,
      encryptedValue: identical(encryptedValue, kUnsetSentinel)
          ? this.encryptedValue
          : encryptedValue as String?,
      metadata: _pick(metadata, this.metadata),
      subagentRunId: _pick(subagentRunId, this.subagentRunId),
    );
  }
}

/// System message with required content.
///
/// Represents system-level instructions or context provided to the agent.
final class SystemMessage extends Message {
  @override
  final String content;

  const SystemMessage({
    required super.id,
    required this.content,
    super.name,
    super.encryptedValue,
    super.metadata,
    super.subagentRunId,
  }) : super(role: MessageRole.system);

  factory SystemMessage.fromJson(Map<String, dynamic> json) {
    return SystemMessage(
      id: JsonDecoder.requireField<String>(json, 'id'),
      content: JsonDecoder.requireField<String>(json, 'content'),
      name: JsonDecoder.optionalField<String>(json, 'name'),
      encryptedValue: JsonDecoder.optionalEitherField<String>(
        json,
        'encryptedValue',
        'encrypted_value',
      ),
      metadata: _readMetadata(json),
      subagentRunId: _readSubagentRunId(json),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'role': role.value,
        'content': content,
        if (name != null) 'name': name,
        if (encryptedValue != null) 'encryptedValue': encryptedValue,
        ..._attribution(this),
      };

  // `name` and `encryptedValue` are nullable on the parent — sentinel
  // for explicit-clear semantics.
  @override
  SystemMessage copyWith({
    String? id,
    String? content,
    Object? name = kUnsetSentinel,
    Object? encryptedValue = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
    Object? subagentRunId = kUnsetSentinel,
  }) {
    return SystemMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      name: identical(name, kUnsetSentinel) ? this.name : name as String?,
      encryptedValue: identical(encryptedValue, kUnsetSentinel)
          ? this.encryptedValue
          : encryptedValue as String?,
      metadata: _pick(metadata, this.metadata),
      subagentRunId: _pick(subagentRunId, this.subagentRunId),
    );
  }
}

/// Assistant message with optional content and tool calls.
///
/// Represents responses from the AI assistant, which may include
/// text content and/or tool call requests.
final class AssistantMessage extends Message {
  final List<ToolCall>? toolCalls;

  const AssistantMessage({
    required super.id,
    super.content,
    super.name,
    this.toolCalls,
    super.encryptedValue,
    super.metadata,
    super.subagentRunId,
  }) : super(role: MessageRole.assistant);

  factory AssistantMessage.fromJson(Map<String, dynamic> json) {
    // KEY-level dual-key resolution with eager element-type validation.
    // Documented precedence rule (see [JsonDecoder.requireEitherField]
    // dartdoc): if camelCase `toolCalls` is present, it wins even when the
    // list is empty; snake_case `tool_calls` is consulted ONLY when
    // camelCase is absent. The pre-fix `??`-on-value chain incorrectly
    // surfaced `tool_calls` whenever camelCase resolved to null OR an
    // empty list — silently dropping snake_case data on payloads that
    // (incorrectly) carry both keys. The regression test
    // `message_test.dart:401-446` ("AssistantMessage.fromJson dual-key
    // precedence") pins this contract.
    //
    // Element-type validation: `optionalEitherListField` reports
    // `field: 'toolCalls[$i]'` on a malformed nested element rather than
    // letting a raw `TypeError` leak from the `as Map<String, dynamic>`
    // cast — same convention as `MessagesSnapshotEvent.fromJson`.
    final rawToolCalls =
        JsonDecoder.optionalEitherListField<Map<String, dynamic>>(
      json,
      'toolCalls',
      'tool_calls',
    );
    return AssistantMessage(
      id: JsonDecoder.requireField<String>(json, 'id'),
      content: JsonDecoder.optionalField<String>(json, 'content'),
      name: JsonDecoder.optionalField<String>(json, 'name'),
      toolCalls: rawToolCalls == null
          ? null
          : () {
              final result = <ToolCall>[];
              for (var i = 0; i < rawToolCalls.length; i++) {
                try {
                  result.add(ToolCall.fromJson(rawToolCalls[i]));
                } catch (e) {
                  if (e is AGUIValidationError) {
                    // Omit `json:` — ToolCall.fromJson can set e.json to a
                    // payload with sensitive `arguments`. Preserve `cause:`
                    // when the inner error already scrubbed its own `json:`
                    // (cipher-aware path) so the stack trace survives.
                    throw AGUIValidationError(
                      message: e.message,
                      field: e.field != null
                          ? 'toolCalls[$i].${e.field}'
                          : 'toolCalls[$i]',
                      value: e.value,
                      cause: e.json == null ? e : null,
                    );
                  }
                  throw AGUIValidationError(
                    message: 'Failed to decode tool call at index $i: $e',
                    field: 'toolCalls[$i]',
                    cause: e,
                  );
                }
              }
              return result;
            }(),
      encryptedValue: JsonDecoder.optionalEitherField<String>(
        json,
        'encryptedValue',
        'encrypted_value',
      ),
      metadata: _readMetadata(json),
      subagentRunId: _readSubagentRunId(json),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        // Emit `toolCalls` whenever the in-memory field is non-null, even
        // when empty, so the round-trip `fromJson(m.toJson()) == m` is
        // symmetric. The previous `&& toolCalls!.isNotEmpty` guard dropped
        // the key on empty lists, which decoded back to `null` instead of
        // `[]` and made tests that depend on field-by-field equality
        // surprising.
        if (toolCalls != null)
          'toolCalls': toolCalls!.map((tc) => tc.toJson()).toList(),
      };

  // See [kUnsetSentinel] for the sentinel rationale. `content`,
  // `name`, `toolCalls`, and `encryptedValue` are all nullable on
  // `AssistantMessage`, so callers may legitimately want to clear any
  // of them via `copyWith`.
  @override
  AssistantMessage copyWith({
    String? id,
    Object? content = kUnsetSentinel,
    Object? name = kUnsetSentinel,
    Object? toolCalls = kUnsetSentinel,
    Object? encryptedValue = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
    Object? subagentRunId = kUnsetSentinel,
  }) {
    return AssistantMessage(
      id: id ?? this.id,
      content: identical(content, kUnsetSentinel)
          ? this.content
          : content as String?,
      name: identical(name, kUnsetSentinel) ? this.name : name as String?,
      toolCalls: identical(toolCalls, kUnsetSentinel)
          ? this.toolCalls
          : toolCalls as List<ToolCall>?,
      encryptedValue: identical(encryptedValue, kUnsetSentinel)
          ? this.encryptedValue
          : encryptedValue as String?,
      metadata: _pick(metadata, this.metadata),
      subagentRunId: _pick(subagentRunId, this.subagentRunId),
    );
  }
}

/// User message with text or multimodal content.
///
/// Represents input from the user in the conversation. The content is a union
/// of plain text or an ordered list of multimodal parts, modeled by
/// [MessageContent]. Use the default constructor for text, or
/// [UserMessage.multimodal] for a list of [ContentPart] parts.
class UserMessage extends Message {
  /// The user message content: [TextContent] or [MultimodalContent].
  final MessageContent messageContent;

  /// Creates a text user message; [content] is wrapped in [TextContent].
  ///
  /// Not `const` because it wraps [content] at runtime. For a compile-time
  /// constant, use [UserMessage.fromContent] with a `const` [TextContent].
  UserMessage({
    required super.id,
    required String content,
    super.name,
    super.encryptedValue,
    super.metadata,
    super.subagentRunId,
  })  : messageContent = TextContent(content),
        super(role: MessageRole.user);

  /// Creates a multimodal user message from an ordered list of [parts].
  UserMessage.multimodal({
    required super.id,
    required List<ContentPart> parts,
    super.name,
    super.encryptedValue,
    super.metadata,
    super.subagentRunId,
  })  : messageContent = MultimodalContent(parts),
        super(role: MessageRole.user);

  /// Creates a user message from a [MessageContent] union value.
  const UserMessage.fromContent({
    required super.id,
    required this.messageContent,
    super.name,
    super.encryptedValue,
    super.metadata,
    super.subagentRunId,
  }) : super(role: MessageRole.user);

  factory UserMessage.fromJson(Map<String, dynamic> json) {
    return UserMessage.fromContent(
      id: JsonDecoder.requireField<String>(json, 'id'),
      messageContent: MessageContent.fromJson(json['content']),
      name: JsonDecoder.optionalField<String>(json, 'name'),
      encryptedValue: JsonDecoder.optionalEitherField<String>(
        json,
        'encryptedValue',
        'encrypted_value',
      ),
      metadata: _readMetadata(json),
      subagentRunId: _readSubagentRunId(json),
    );
  }

  /// The text of this message, or `null` when the content is multimodal.
  ///
  /// Projects [messageContent] so existing text-only readers keep working.
  @override
  String? get content => switch (messageContent) {
        TextContent(:final text) => text,
        MultimodalContent() => null,
      };

  @override
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'role': role.value,
        'content': messageContent.toJson(),
        if (name != null) 'name': name,
        if (encryptedValue != null) 'encryptedValue': encryptedValue,
        ..._attribution(this),
      };

  // `name` and `encryptedValue` are nullable on the parent — sentinel
  // for explicit-clear semantics.
  @override
  UserMessage copyWith({
    String? id,
    MessageContent? messageContent,
    Object? name = kUnsetSentinel,
    Object? encryptedValue = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
    Object? subagentRunId = kUnsetSentinel,
  }) {
    return UserMessage.fromContent(
      id: id ?? this.id,
      messageContent: messageContent ?? this.messageContent,
      name: identical(name, kUnsetSentinel) ? this.name : name as String?,
      encryptedValue: identical(encryptedValue, kUnsetSentinel)
          ? this.encryptedValue
          : encryptedValue as String?,
      metadata: _pick(metadata, this.metadata),
      subagentRunId: _pick(subagentRunId, this.subagentRunId),
    );
  }
}

/// Tool message with tool call result.
///
/// Contains the result of a tool execution, linked to a specific tool call
/// via the [toolCallId] field. Since protocol 1.0 the result is text or an
/// ordered list of [ContentPart]s, modeled by [messageContent]; [content]
/// projects it to text. The optional [encryptedValue] carries an opaque
/// cipher payload that a Dart proxy must forward verbatim to a downstream
/// agent.
final class ToolMessage extends Message {
  /// The result: [TextContent] or [MultimodalContent].
  final MessageContent messageContent;
  final String toolCallId;
  final String? error;

  /// Creates a tool message whose result is text.
  ToolMessage({
    required super.id,
    required String content,
    required this.toolCallId,
    this.error,
    super.encryptedValue,
    super.metadata,
    super.subagentRunId,
  })  : messageContent = TextContent(content),
        super(role: MessageRole.tool);

  /// Creates a tool message from a [MessageContent] value.
  const ToolMessage.fromContent({
    required super.id,
    required this.messageContent,
    required this.toolCallId,
    this.error,
    super.encryptedValue,
    super.metadata,
    super.subagentRunId,
  }) : super(role: MessageRole.tool);

  factory ToolMessage.fromJson(Map<String, dynamic> json) {
    return ToolMessage.fromContent(
      id: JsonDecoder.requireField<String>(json, 'id'),
      messageContent: MessageContent.fromJson(json['content']),
      toolCallId: JsonDecoder.requireEitherField<String>(
        json,
        'toolCallId',
        'tool_call_id',
      ),
      error: JsonDecoder.optionalField<String>(json, 'error'),
      encryptedValue: JsonDecoder.optionalEitherField<String>(
        json,
        'encryptedValue',
        'encrypted_value',
      ),
      metadata: _readMetadata(json),
      subagentRunId: _readSubagentRunId(json),
    );
  }

  /// The result as text; for a list of parts, its text parts joined.
  /// See [MessageContent.text].
  @override
  String get content => messageContent.text;

  // ToolMessage's constructors do not accept `name`, so the inherited
  // Message.name is always null and is not emitted.
  @override
  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'role': role.value,
        'content': messageContent.toJson(),
        if (encryptedValue != null) 'encryptedValue': encryptedValue,
        'toolCallId': toolCallId,
        if (error != null) 'error': error,
        ..._attribution(this),
      };

  @override
  ToolMessage copyWith({
    String? id,
    MessageContent? messageContent,
    String? toolCallId,
    Object? error = kUnsetSentinel,
    Object? encryptedValue = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
    Object? subagentRunId = kUnsetSentinel,
  }) {
    return ToolMessage.fromContent(
      id: id ?? this.id,
      messageContent: messageContent ?? this.messageContent,
      toolCallId: toolCallId ?? this.toolCallId,
      error: _pick(error, this.error),
      encryptedValue: _pick(encryptedValue, this.encryptedValue),
      metadata: _pick(metadata, this.metadata),
      subagentRunId: _pick(subagentRunId, this.subagentRunId),
    );
  }
}

/// Activity message embedded in a `MESSAGES_SNAPSHOT` payload.
///
/// Mirrors the canonical TypeScript `ActivityMessageSchema`
/// (`sdks/typescript/packages/core/src/types.ts`) and the Python
/// `ActivityMessage` model (`sdks/python/ag_ui/core/types.py`). The wire
/// shape is `{id, role: 'activity', activityType, content}` where
/// `content` is a JSON object (`z.record(z.any())` / `Dict[str, Any]`).
///
/// The Dart in-memory accessor for the wire `content` field is named
/// [activityContent] to avoid shadowing the parent [Message.content]
/// (which is `String?`). The wire key remains `content` in [toJson] /
/// [fromJson] for protocol parity.
///
/// **`encryptedValue` note.** `ActivityMessage` inherits [encryptedValue]
/// from [Message] but intentionally does not expose it in the constructor,
/// [fromJson], or [toJson]. In the canonical protocol `ActivityMessage` is
/// NOT a `BaseMessage` extension (unlike Developer/System/Assistant/User/Tool
/// messages), so cipher-payload forwarding does not apply here. If the wire
/// payload contains `encryptedValue` / `encrypted_value`, [fromJson] strips
/// it silently (matching TS zod-default strip behavior). In-memory instances
/// constructed via [copyWith] on a parent [Message] may inherit the field,
/// but [toJson] never emits it.
final class ActivityMessage extends Message {
  final String activityType;
  final Map<String, dynamic> activityContent;

  const ActivityMessage({
    required super.id,
    required this.activityType,
    required this.activityContent,
    super.metadata,
    super.subagentRunId,
  }) : super(role: MessageRole.activity);

  // ActivityMessage never carries cipher data — override the inherited getter
  // to guarantee null. fromJson silently strips any inbound encryptedValue;
  // this override ensures no in-memory path (copyWith, subclassing) can
  // accidentally set it, making the cipher-scrub predicate in
  // MessagesSnapshotEvent.fromJson permanently reliable.
  @override
  String? get encryptedValue => null;

  factory ActivityMessage.fromJson(Map<String, dynamic> json) {
    // `ActivityMessage` is NOT a `BaseMessage` extension in the canonical
    // protocol — cipher-payload forwarding does not apply. Strip any inbound
    // `encryptedValue` / `encrypted_value` silently, matching TS zod-default
    // strip behavior. A hard-fail here would make Dart the only SDK that tears
    // down the stream when a proxy emits the field (TS strips, Python preserves).
    return ActivityMessage(
      id: JsonDecoder.requireField<String>(json, 'id'),
      activityType: JsonDecoder.requireEitherField<String>(
        json,
        'activityType',
        'activity_type',
      ),
      activityContent:
          JsonDecoder.requireField<Map<String, dynamic>>(json, 'content'),
      metadata: _readMetadata(json),
      subagentRunId: _readSubagentRunId(json),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        // Explicitly skip super.toJson() — the inherited Message.content field
        // must not appear in the wire output (activityContent is the `content`
        // key here). Using ...super.toJson() would rely on map-spread
        // overwrite order to mask any future super.content emission.
        if (id != null) 'id': id,
        'role': role.value,
        'activityType': activityType,
        'content': activityContent,
        ..._attribution(this),
      };

  // `id` is nullable on the parent `Message` — use the sentinel so a caller
  // can explicitly clear it via `copyWith(id: null)`. The bare `?? this.id`
  // pattern cannot distinguish "omitted" from "explicitly null".
  @override
  ActivityMessage copyWith({
    Object? id = kUnsetSentinel,
    String? activityType,
    Map<String, dynamic>? activityContent,
    Object? metadata = kUnsetSentinel,
    Object? subagentRunId = kUnsetSentinel,
  }) {
    return ActivityMessage(
      id: identical(id, kUnsetSentinel) ? this.id : id as String?,
      activityType: activityType ?? this.activityType,
      activityContent: activityContent ?? this.activityContent,
      metadata: _pick(metadata, this.metadata),
      subagentRunId: _pick(subagentRunId, this.subagentRunId),
    );
  }
}

/// Reasoning message emitted by models that expose their chain-of-thought.
///
/// Mirrors `ReasoningMessage` in the Python and TypeScript reference SDKs.
/// [content] is the visible reasoning text; [thinking] is an opaque
/// extended-thinking blob; [encryptedValue] carries the encrypted thinking
/// payload when the server uses encrypted extended thinking.
class ReasoningMessage extends Message {
  /// Optional visible reasoning / chain-of-thought text.
  @override
  final String? content;

  /// Optional opaque extended-thinking blob.
  final String? thinking;

  const ReasoningMessage({
    super.id,
    this.content,
    this.thinking,
    super.encryptedValue,
    super.metadata,
    super.subagentRunId,
  }) : super(role: MessageRole.reasoning);

  factory ReasoningMessage.fromJson(Map<String, dynamic> json) {
    return ReasoningMessage(
      id: JsonDecoder.optionalField<String>(json, 'id'),
      content: JsonDecoder.optionalField<String>(json, 'content'),
      thinking: JsonDecoder.optionalField<String>(json, 'thinking'),
      encryptedValue: JsonDecoder.optionalEitherField<String>(
        json,
        'encryptedValue',
        'encrypted_value',
      ),
      metadata: _readMetadata(json),
      subagentRunId: _readSubagentRunId(json),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (thinking != null) 'thinking': thinking,
      };

  // `encryptedValue` is nullable on the parent — sentinel lets callers clear it.
  @override
  ReasoningMessage copyWith({
    String? id,
    String? content,
    String? thinking,
    Object? encryptedValue = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
    Object? subagentRunId = kUnsetSentinel,
  }) {
    return ReasoningMessage(
      id: id ?? this.id,
      content: content ?? this.content,
      thinking: thinking ?? this.thinking,
      encryptedValue: identical(encryptedValue, kUnsetSentinel)
          ? this.encryptedValue
          : encryptedValue as String?,
      metadata: _pick(metadata, this.metadata),
      subagentRunId: _pick(subagentRunId, this.subagentRunId),
    );
  }
}

/// Reads a MIME type from JSON, accepting both `mimeType` and `mime_type`.
String? _readMimeType(Map<String, dynamic> json) =>
    JsonDecoder.optionalEitherField<String>(json, 'mimeType', 'mime_type');

/// Where a media [ContentPart]'s bytes are.
///
/// A discriminated union on `type`: [DataSource] (inline data, e.g. base64),
/// [UrlSource] (a remote URL), or [FileSource] (a handle a model provider
/// issued for bytes already uploaded to it). Use [PartSource.fromJson] to
/// decode.
sealed class PartSource extends AGUIModel {
  const PartSource();

  /// The source discriminator: `data`, `url` or `file`.
  String get sourceType;

  /// Decodes a [PartSource] from JSON, dispatching on `type`.
  factory PartSource.fromJson(Map<String, dynamic> json) {
    final type = JsonDecoder.requireField<String>(json, 'type');
    switch (type) {
      case 'data':
        return DataSource.fromJson(json);
      case 'url':
        return UrlSource.fromJson(json);
      case 'file':
        return FileSource.fromJson(json);
      default:
        throw AGUIValidationError(
          message: 'Invalid part source type: $type',
          field: 'type',
          value: type,
          json: json,
        );
    }
  }
}

/// The 0.x name of [PartSource].
@Deprecated('Use PartSource. Renamed in protocol 1.0.')
typedef InputContentSource = PartSource;

/// Inline content source carrying a data payload (e.g. base64-encoded bytes).
///
/// [mimeType] is required for data sources.
class DataSource extends PartSource {
  /// The inline data payload, typically base64-encoded.
  final String value;

  /// The MIME type of [value]. Required.
  final String mimeType;

  const DataSource({required this.value, required this.mimeType});

  @override
  String get sourceType => 'data';

  factory DataSource.fromJson(Map<String, dynamic> json) {
    final mimeType = _readMimeType(json);
    if (mimeType == null) {
      throw AGUIValidationError(
        message: 'DataSource requires a mimeType',
        field: 'mimeType',
        json: json,
      );
    }
    return DataSource(
      value: JsonDecoder.requireField<String>(json, 'value'),
      mimeType: mimeType,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': sourceType,
        'value': value,
        'mimeType': mimeType,
      };

  @override
  DataSource copyWith({String? value, String? mimeType}) => DataSource(
        value: value ?? this.value,
        mimeType: mimeType ?? this.mimeType,
      );
}

/// Remote content source referenced by URL.
///
/// [mimeType] is optional for URL sources.
class UrlSource extends PartSource {
  /// The URL of the content.
  final String value;

  /// The optional MIME type of the referenced content.
  final String? mimeType;

  const UrlSource({required this.value, this.mimeType});

  @override
  String get sourceType => 'url';

  factory UrlSource.fromJson(Map<String, dynamic> json) => UrlSource(
        value: JsonDecoder.requireField<String>(json, 'value'),
        mimeType: _readMimeType(json),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': sourceType,
        'value': value,
        if (mimeType != null) 'mimeType': mimeType,
      };

  @override
  UrlSource copyWith({String? value, Object? mimeType = kUnsetSentinel}) =>
      UrlSource(
        value: value ?? this.value,
        mimeType: _pick(mimeType, this.mimeType),
      );
}

/// A handle a model provider issued for bytes already uploaded to it.
///
/// [value] is that handle (for example an OpenAI file id), never a URL: an
/// agent that cannot hand it to [provider] should skip the part with a
/// warning, as for any part the model cannot take.
class FileSource extends PartSource {
  /// The provider's handle for the uploaded bytes.
  final String value;

  /// The provider that issued [value], when the producer named one.
  final String? provider;

  /// The MIME type of the uploaded bytes, when known.
  final String? mimeType;

  const FileSource({required this.value, this.provider, this.mimeType});

  @override
  String get sourceType => 'file';

  factory FileSource.fromJson(Map<String, dynamic> json) => FileSource(
        value: JsonDecoder.requireField<String>(json, 'value'),
        provider: JsonDecoder.optionalField<String>(json, 'provider'),
        mimeType: _readMimeType(json),
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': sourceType,
        'value': value,
        if (provider != null) 'provider': provider,
        if (mimeType != null) 'mimeType': mimeType,
      };

  @override
  FileSource copyWith({
    String? value,
    Object? provider = kUnsetSentinel,
    Object? mimeType = kUnsetSentinel,
  }) =>
      FileSource(
        value: value ?? this.value,
        provider: _pick(provider, this.provider),
        mimeType: _pick(mimeType, this.mimeType),
      );
}

/// One typed part of a message's content.
///
/// A discriminated union on `type`: [TextPart], [ImagePart], [AudioPart],
/// [VideoPart] or [DocumentPart]. Every part has an optional [id] and
/// optional free-form [metadata]. Use [ContentPart.fromJson] to decode.
///
/// The 0.x `binary` part is gone: protocol 1.0 rejects it, and so does
/// [ContentPart.fromJson]. Send a media part with a [PartSource] instead.
sealed class ContentPart extends AGUIModel with TypeDiscriminator {
  /// An identifier for this part, unique within its message.
  final String? id;

  /// Free-form, provider-specific metadata. Serialized only when non-null.
  final Object? metadata;

  const ContentPart({this.id, this.metadata});

  /// Decodes a [ContentPart] from JSON, dispatching on `type`.
  factory ContentPart.fromJson(Map<String, dynamic> json) {
    final type = JsonDecoder.requireField<String>(json, 'type');
    switch (type) {
      case 'text':
        return TextPart.fromJson(json);
      case 'image':
        return ImagePart.fromJson(json);
      case 'audio':
        return AudioPart.fromJson(json);
      case 'video':
        return VideoPart.fromJson(json);
      case 'document':
        return DocumentPart.fromJson(json);
      default:
        throw AGUIValidationError(
          message: 'Invalid content part type: $type',
          field: 'type',
          value: type,
          json: json,
        );
    }
  }

  /// The wire fields every part shares, after `type`.
  Map<String, dynamic> _common() => {
        if (id != null) 'id': id,
        if (metadata != null) 'metadata': metadata,
      };
}

/// The 0.x name of [ContentPart].
@Deprecated('Use ContentPart. Renamed in protocol 1.0.')
typedef InputContent = ContentPart;

/// Plain text part of a message's content.
class TextPart extends ContentPart {
  /// The text payload.
  final String text;

  const TextPart(this.text, {super.id, super.metadata});

  @override
  String get type => 'text';

  factory TextPart.fromJson(Map<String, dynamic> json) => TextPart(
        JsonDecoder.requireField<String>(json, 'text'),
        id: JsonDecoder.optionalField<String>(json, 'id'),
        metadata: json['metadata'],
      );

  @override
  Map<String, dynamic> toJson() => {'type': type, 'text': text, ..._common()};

  @override
  TextPart copyWith({
    String? text,
    Object? id = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
  }) =>
      TextPart(
        text ?? this.text,
        id: _pick(id, this.id),
        metadata: _pick(metadata, this.metadata),
      );
}

/// The 0.x name of [TextPart].
@Deprecated('Use TextPart. Renamed in protocol 1.0.')
typedef TextInputContent = TextPart;

/// A media part: an image, audio clip, video or document, by [source].
sealed class MediaPart extends ContentPart {
  /// Where the part's bytes are.
  final PartSource source;

  const MediaPart({required this.source, super.id, super.metadata});

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'source': source.toJson(),
        ..._common(),
      };
}

/// Parses the fields every media part shares.
({PartSource source, String? id, Object? metadata}) _parseMediaPart(
  Map<String, dynamic> json,
  String type,
) {
  final rawSource = json['source'];
  if (rawSource is! Map<String, dynamic>) {
    throw AGUIValidationError(
      message: '$type part requires a source object',
      field: 'source',
      value: rawSource,
      json: json,
    );
  }
  return (
    source: PartSource.fromJson(rawSource),
    id: JsonDecoder.optionalField<String>(json, 'id'),
    metadata: json['metadata'],
  );
}

/// Image part of a message's content.
class ImagePart extends MediaPart {
  const ImagePart({required super.source, super.id, super.metadata});

  @override
  String get type => 'image';

  factory ImagePart.fromJson(Map<String, dynamic> json) {
    final p = _parseMediaPart(json, 'image');
    return ImagePart(source: p.source, id: p.id, metadata: p.metadata);
  }

  @override
  ImagePart copyWith({
    PartSource? source,
    Object? id = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
  }) =>
      ImagePart(
        source: source ?? this.source,
        id: _pick(id, this.id),
        metadata: _pick(metadata, this.metadata),
      );
}

/// The 0.x name of [ImagePart].
@Deprecated('Use ImagePart. Renamed in protocol 1.0.')
typedef ImageInputContent = ImagePart;

/// Audio part of a message's content.
class AudioPart extends MediaPart {
  const AudioPart({required super.source, super.id, super.metadata});

  @override
  String get type => 'audio';

  factory AudioPart.fromJson(Map<String, dynamic> json) {
    final p = _parseMediaPart(json, 'audio');
    return AudioPart(source: p.source, id: p.id, metadata: p.metadata);
  }

  @override
  AudioPart copyWith({
    PartSource? source,
    Object? id = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
  }) =>
      AudioPart(
        source: source ?? this.source,
        id: _pick(id, this.id),
        metadata: _pick(metadata, this.metadata),
      );
}

/// The 0.x name of [AudioPart].
@Deprecated('Use AudioPart. Renamed in protocol 1.0.')
typedef AudioInputContent = AudioPart;

/// Video part of a message's content.
class VideoPart extends MediaPart {
  const VideoPart({required super.source, super.id, super.metadata});

  @override
  String get type => 'video';

  factory VideoPart.fromJson(Map<String, dynamic> json) {
    final p = _parseMediaPart(json, 'video');
    return VideoPart(source: p.source, id: p.id, metadata: p.metadata);
  }

  @override
  VideoPart copyWith({
    PartSource? source,
    Object? id = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
  }) =>
      VideoPart(
        source: source ?? this.source,
        id: _pick(id, this.id),
        metadata: _pick(metadata, this.metadata),
      );
}

/// The 0.x name of [VideoPart].
@Deprecated('Use VideoPart. Renamed in protocol 1.0.')
typedef VideoInputContent = VideoPart;

/// Document part of a message's content.
class DocumentPart extends MediaPart {
  const DocumentPart({required super.source, super.id, super.metadata});

  @override
  String get type => 'document';

  factory DocumentPart.fromJson(Map<String, dynamic> json) {
    final p = _parseMediaPart(json, 'document');
    return DocumentPart(source: p.source, id: p.id, metadata: p.metadata);
  }

  @override
  DocumentPart copyWith({
    PartSource? source,
    Object? id = kUnsetSentinel,
    Object? metadata = kUnsetSentinel,
  }) =>
      DocumentPart(
        source: source ?? this.source,
        id: _pick(id, this.id),
        metadata: _pick(metadata, this.metadata),
      );
}

/// The 0.x name of [DocumentPart].
@Deprecated('Use DocumentPart. Renamed in protocol 1.0.')
typedef DocumentInputContent = DocumentPart;

/// Message content: plain text or an ordered list of [ContentPart]s.
///
/// The wire's `string | ContentPart[]`, carried by [UserMessage],
/// [ToolMessage] and `ToolCallResultEvent`. [toJson] returns a `String` for
/// [TextContent] or a `List` for [MultimodalContent].
///
/// Unlike the other models this does not extend `AGUIModel`: its [toJson] must
/// return a bare `String` or `List`, not a `Map<String, dynamic>`.
sealed class MessageContent {
  const MessageContent();

  /// Serializes to a JSON `String` (text) or `List` (parts).
  Object toJson();

  /// The content as text: the string itself, or the text parts joined in
  /// order with nothing between them. Media parts contribute nothing; check
  /// [hasMedia] when that loss matters.
  String get text;

  /// Whether flattening to [text] drops anything: true when any part is a
  /// media part.
  bool get hasMedia;

  /// Decodes from a raw `content` value: a `String` or a `List` of parts.
  factory MessageContent.fromJson(Object? raw) {
    if (raw is String) {
      return TextContent(raw);
    }
    if (raw is List) {
      final parts = <ContentPart>[];
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map<String, dynamic>) {
          throw AGUIValidationError(
            message: 'Content part at index $i must be an object',
            field: 'content[$i]',
            value: item,
          );
        }
        try {
          parts.add(ContentPart.fromJson(item));
        } on AGUIValidationError catch (e) {
          throw AGUIValidationError(
            message: 'Invalid content part at index $i: ${e.message}',
            field: 'content[$i]',
            value: item,
          );
        }
      }
      // Decode is tolerant: an empty list is a structurally valid
      // MultimodalContent (the schema's array has no minimum). The
      // non-empty invariant for a user message is enforced on the send side
      // by Validators.validateMessageContent.
      return MultimodalContent(parts);
    }
    throw AGUIValidationError(
      message: 'Content must be a String or a List of parts',
      field: 'content',
      value: raw,
    );
  }
}

/// The 0.x name of [MessageContent], from when only a user message had it.
@Deprecated('Use MessageContent. Tool results share it since protocol 1.0.')
typedef UserMessageContent = MessageContent;

/// Plain-text message content. Serializes to a JSON `String`.
class TextContent extends MessageContent {
  @override
  final String text;

  const TextContent(this.text);

  @override
  bool get hasMedia => false;

  @override
  String toJson() => text;
}

/// Message content as an ordered list of parts. Serializes to a JSON `List`.
class MultimodalContent extends MessageContent {
  /// The ordered list of content parts.
  final List<ContentPart> parts;

  const MultimodalContent(this.parts);

  @override
  String get text => parts.whereType<TextPart>().map((p) => p.text).join();

  @override
  bool get hasMedia => parts.any((p) => p is MediaPart);

  @override
  List<Map<String, dynamic>> toJson() =>
      parts.map((part) => part.toJson()).toList();
}

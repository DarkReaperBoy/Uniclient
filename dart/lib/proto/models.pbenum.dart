//
//  Generated code. Do not modify.
//  source: models.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class ChatType extends $pb.ProtobufEnum {
  static const ChatType CHAT_TYPE_UNSPECIFIED = ChatType._(0, _omitEnumNames ? '' : 'CHAT_TYPE_UNSPECIFIED');
  static const ChatType CHAT_TYPE_DM = ChatType._(1, _omitEnumNames ? '' : 'CHAT_TYPE_DM');
  static const ChatType CHAT_TYPE_GROUP = ChatType._(2, _omitEnumNames ? '' : 'CHAT_TYPE_GROUP');
  static const ChatType CHAT_TYPE_CHANNEL = ChatType._(3, _omitEnumNames ? '' : 'CHAT_TYPE_CHANNEL');
  static const ChatType CHAT_TYPE_TOPIC = ChatType._(4, _omitEnumNames ? '' : 'CHAT_TYPE_TOPIC');

  static const $core.List<ChatType> values = <ChatType> [
    CHAT_TYPE_UNSPECIFIED,
    CHAT_TYPE_DM,
    CHAT_TYPE_GROUP,
    CHAT_TYPE_CHANNEL,
    CHAT_TYPE_TOPIC,
  ];

  static final $core.Map<$core.int, ChatType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ChatType? valueOf($core.int value) => _byValue[value];

  const ChatType._($core.int v, $core.String n) : super(v, n);
}

class MessageStatus extends $pb.ProtobufEnum {
  static const MessageStatus MESSAGE_STATUS_UNSPECIFIED = MessageStatus._(0, _omitEnumNames ? '' : 'MESSAGE_STATUS_UNSPECIFIED');
  static const MessageStatus MESSAGE_STATUS_SENDING = MessageStatus._(1, _omitEnumNames ? '' : 'MESSAGE_STATUS_SENDING');
  static const MessageStatus MESSAGE_STATUS_SENT = MessageStatus._(2, _omitEnumNames ? '' : 'MESSAGE_STATUS_SENT');
  static const MessageStatus MESSAGE_STATUS_DELIVERED = MessageStatus._(3, _omitEnumNames ? '' : 'MESSAGE_STATUS_DELIVERED');
  static const MessageStatus MESSAGE_STATUS_READ = MessageStatus._(4, _omitEnumNames ? '' : 'MESSAGE_STATUS_READ');
  static const MessageStatus MESSAGE_STATUS_FAILED = MessageStatus._(5, _omitEnumNames ? '' : 'MESSAGE_STATUS_FAILED');

  static const $core.List<MessageStatus> values = <MessageStatus> [
    MESSAGE_STATUS_UNSPECIFIED,
    MESSAGE_STATUS_SENDING,
    MESSAGE_STATUS_SENT,
    MESSAGE_STATUS_DELIVERED,
    MESSAGE_STATUS_READ,
    MESSAGE_STATUS_FAILED,
  ];

  static final $core.Map<$core.int, MessageStatus> _byValue = $pb.ProtobufEnum.initByValue(values);
  static MessageStatus? valueOf($core.int value) => _byValue[value];

  const MessageStatus._($core.int v, $core.String n) : super(v, n);
}

class UpdateType extends $pb.ProtobufEnum {
  static const UpdateType UPDATE_TYPE_UNSPECIFIED = UpdateType._(0, _omitEnumNames ? '' : 'UPDATE_TYPE_UNSPECIFIED');
  static const UpdateType UPDATE_TYPE_NEW_MESSAGE = UpdateType._(1, _omitEnumNames ? '' : 'UPDATE_TYPE_NEW_MESSAGE');
  static const UpdateType UPDATE_TYPE_EDIT_MESSAGE = UpdateType._(2, _omitEnumNames ? '' : 'UPDATE_TYPE_EDIT_MESSAGE');
  static const UpdateType UPDATE_TYPE_DELETE_MESSAGE = UpdateType._(3, _omitEnumNames ? '' : 'UPDATE_TYPE_DELETE_MESSAGE');
  static const UpdateType UPDATE_TYPE_READ_STATE = UpdateType._(4, _omitEnumNames ? '' : 'UPDATE_TYPE_READ_STATE');
  static const UpdateType UPDATE_TYPE_USER_STATUS = UpdateType._(5, _omitEnumNames ? '' : 'UPDATE_TYPE_USER_STATUS');
  static const UpdateType UPDATE_TYPE_TYPING = UpdateType._(6, _omitEnumNames ? '' : 'UPDATE_TYPE_TYPING');
  static const UpdateType UPDATE_TYPE_CALL_STATE = UpdateType._(7, _omitEnumNames ? '' : 'UPDATE_TYPE_CALL_STATE');
  static const UpdateType UPDATE_TYPE_GROUP_MEMBERS = UpdateType._(8, _omitEnumNames ? '' : 'UPDATE_TYPE_GROUP_MEMBERS');
  static const UpdateType UPDATE_TYPE_VERIFICATION = UpdateType._(9, _omitEnumNames ? '' : 'UPDATE_TYPE_VERIFICATION');
  static const UpdateType UPDATE_TYPE_CONNECTIVITY = UpdateType._(10, _omitEnumNames ? '' : 'UPDATE_TYPE_CONNECTIVITY');

  static const $core.List<UpdateType> values = <UpdateType> [
    UPDATE_TYPE_UNSPECIFIED,
    UPDATE_TYPE_NEW_MESSAGE,
    UPDATE_TYPE_EDIT_MESSAGE,
    UPDATE_TYPE_DELETE_MESSAGE,
    UPDATE_TYPE_READ_STATE,
    UPDATE_TYPE_USER_STATUS,
    UPDATE_TYPE_TYPING,
    UPDATE_TYPE_CALL_STATE,
    UPDATE_TYPE_GROUP_MEMBERS,
    UPDATE_TYPE_VERIFICATION,
    UPDATE_TYPE_CONNECTIVITY,
  ];

  static final $core.Map<$core.int, UpdateType> _byValue = $pb.ProtobufEnum.initByValue(values);
  static UpdateType? valueOf($core.int value) => _byValue[value];

  const UpdateType._($core.int v, $core.String n) : super(v, n);
}

class CallState extends $pb.ProtobufEnum {
  static const CallState CALL_STATE_UNSPECIFIED = CallState._(0, _omitEnumNames ? '' : 'CALL_STATE_UNSPECIFIED');
  static const CallState CALL_STATE_RINGING = CallState._(1, _omitEnumNames ? '' : 'CALL_STATE_RINGING');
  static const CallState CALL_STATE_CONNECTING = CallState._(2, _omitEnumNames ? '' : 'CALL_STATE_CONNECTING');
  static const CallState CALL_STATE_ACTIVE = CallState._(3, _omitEnumNames ? '' : 'CALL_STATE_ACTIVE');
  static const CallState CALL_STATE_ENDED = CallState._(4, _omitEnumNames ? '' : 'CALL_STATE_ENDED');

  static const $core.List<CallState> values = <CallState> [
    CALL_STATE_UNSPECIFIED,
    CALL_STATE_RINGING,
    CALL_STATE_CONNECTING,
    CALL_STATE_ACTIVE,
    CALL_STATE_ENDED,
  ];

  static final $core.Map<$core.int, CallState> _byValue = $pb.ProtobufEnum.initByValue(values);
  static CallState? valueOf($core.int value) => _byValue[value];

  const CallState._($core.int v, $core.String n) : super(v, n);
}

class AuthMode extends $pb.ProtobufEnum {
  static const AuthMode AUTH_MODE_UNSPECIFIED = AuthMode._(0, _omitEnumNames ? '' : 'AUTH_MODE_UNSPECIFIED');
  static const AuthMode AUTH_MODE_BOT = AuthMode._(1, _omitEnumNames ? '' : 'AUTH_MODE_BOT');
  static const AuthMode AUTH_MODE_USER = AuthMode._(2, _omitEnumNames ? '' : 'AUTH_MODE_USER');

  static const $core.List<AuthMode> values = <AuthMode> [
    AUTH_MODE_UNSPECIFIED,
    AUTH_MODE_BOT,
    AUTH_MODE_USER,
  ];

  static final $core.Map<$core.int, AuthMode> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AuthMode? valueOf($core.int value) => _byValue[value];

  const AuthMode._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');

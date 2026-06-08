//
//  Generated code. Do not modify.
//  source: proto/engine.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use engineEventDescriptor instead')
const EngineEvent$json = {
  '1': 'EngineEvent',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 9, '10': 'type'},
    {'1': 'account_id', '3': 2, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'timestamp_ms', '3': 3, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'data_json', '3': 4, '4': 1, '5': 12, '10': 'dataJson'},
  ],
};

/// Descriptor for `EngineEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineEventDescriptor = $convert.base64Decode(
    'CgtFbmdpbmVFdmVudBISCgR0eXBlGAEgASgJUgR0eXBlEh0KCmFjY291bnRfaWQYAiABKAlSCW'
    'FjY291bnRJZBIhCgx0aW1lc3RhbXBfbXMYAyABKANSC3RpbWVzdGFtcE1zEhsKCWRhdGFfanNv'
    'bhgEIAEoDFIIZGF0YUpzb24=');

@$core.Deprecated('Use accountInfoDescriptor instead')
const AccountInfo$json = {
  '1': 'AccountInfo',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'platform', '3': 2, '4': 1, '5': 9, '10': 'platform'},
    {'1': 'display_name', '3': 3, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'avatar_path', '3': 4, '4': 1, '5': 9, '10': 'avatarPath'},
    {'1': 'sort_order', '3': 5, '4': 1, '5': 5, '10': 'sortOrder'},
    {'1': 'conn_state', '3': 6, '4': 1, '5': 5, '10': 'connState'},
    {'1': 'is_verified', '3': 7, '4': 1, '5': 8, '10': 'isVerified'},
    {'1': 'is_premium', '3': 8, '4': 1, '5': 8, '10': 'isPremium'},
    {'1': 'phone', '3': 9, '4': 1, '5': 9, '10': 'phone'},
    {'1': 'username', '3': 10, '4': 1, '5': 9, '10': 'username'},
    {'1': 'self_user_id', '3': 11, '4': 1, '5': 9, '10': 'selfUserId'},
  ],
};

/// Descriptor for `AccountInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List accountInfoDescriptor = $convert.base64Decode(
    'CgtBY2NvdW50SW5mbxIOCgJpZBgBIAEoCVICaWQSGgoIcGxhdGZvcm0YAiABKAlSCHBsYXRmb3'
    'JtEiEKDGRpc3BsYXlfbmFtZRgDIAEoCVILZGlzcGxheU5hbWUSHwoLYXZhdGFyX3BhdGgYBCAB'
    'KAlSCmF2YXRhclBhdGgSHQoKc29ydF9vcmRlchgFIAEoBVIJc29ydE9yZGVyEh0KCmNvbm5fc3'
    'RhdGUYBiABKAVSCWNvbm5TdGF0ZRIfCgtpc192ZXJpZmllZBgHIAEoCFIKaXNWZXJpZmllZBId'
    'Cgppc19wcmVtaXVtGAggASgIUglpc1ByZW1pdW0SFAoFcGhvbmUYCSABKAlSBXBob25lEhoKCH'
    'VzZXJuYW1lGAogASgJUgh1c2VybmFtZRIgCgxzZWxmX3VzZXJfaWQYCyABKAlSCnNlbGZVc2Vy'
    'SWQ=');

@$core.Deprecated('Use engineInitRequestDescriptor instead')
const EngineInitRequest$json = {
  '1': 'EngineInitRequest',
  '2': [
    {'1': 'config_dir', '3': 1, '4': 1, '5': 9, '10': 'configDir'},
    {'1': 'cache_dir', '3': 2, '4': 1, '5': 9, '10': 'cacheDir'},
    {'1': 'download_dir', '3': 3, '4': 1, '5': 9, '10': 'downloadDir'},
    {'1': 'vault_password', '3': 4, '4': 1, '5': 9, '10': 'vaultPassword'},
  ],
};

/// Descriptor for `EngineInitRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineInitRequestDescriptor = $convert.base64Decode(
    'ChFFbmdpbmVJbml0UmVxdWVzdBIdCgpjb25maWdfZGlyGAEgASgJUgljb25maWdEaXISGwoJY2'
    'FjaGVfZGlyGAIgASgJUghjYWNoZURpchIhCgxkb3dubG9hZF9kaXIYAyABKAlSC2Rvd25sb2Fk'
    'RGlyEiUKDnZhdWx0X3Bhc3N3b3JkGAQgASgJUg12YXVsdFBhc3N3b3Jk');

@$core.Deprecated('Use engineInitResponseDescriptor instead')
const EngineInitResponse$json = {
  '1': 'EngineInitResponse',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
    {'1': 'error', '3': 2, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `EngineInitResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineInitResponseDescriptor = $convert.base64Decode(
    'ChJFbmdpbmVJbml0UmVzcG9uc2USDgoCb2sYASABKAhSAm9rEhQKBWVycm9yGAIgASgJUgVlcn'
    'Jvcg==');

@$core.Deprecated('Use engineListAccountsResponseDescriptor instead')
const EngineListAccountsResponse$json = {
  '1': 'EngineListAccountsResponse',
  '2': [
    {'1': 'accounts', '3': 1, '4': 3, '5': 11, '6': '.uniclient.AccountInfo', '10': 'accounts'},
  ],
};

/// Descriptor for `EngineListAccountsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineListAccountsResponseDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVMaXN0QWNjb3VudHNSZXNwb25zZRIyCghhY2NvdW50cxgBIAMoCzIWLnVuaWNsaW'
    'VudC5BY2NvdW50SW5mb1IIYWNjb3VudHM=');

@$core.Deprecated('Use engineAddAccountRequestDescriptor instead')
const EngineAddAccountRequest$json = {
  '1': 'EngineAddAccountRequest',
  '2': [
    {'1': 'platform', '3': 1, '4': 1, '5': 9, '10': 'platform'},
  ],
};

/// Descriptor for `EngineAddAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineAddAccountRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVBZGRBY2NvdW50UmVxdWVzdBIaCghwbGF0Zm9ybRgBIAEoCVIIcGxhdGZvcm0=');

@$core.Deprecated('Use engineAddAccountResponseDescriptor instead')
const EngineAddAccountResponse$json = {
  '1': 'EngineAddAccountResponse',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineAddAccountResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineAddAccountResponseDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVBZGRBY2NvdW50UmVzcG9uc2USHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lk');

@$core.Deprecated('Use engineRemoveAccountRequestDescriptor instead')
const EngineRemoveAccountRequest$json = {
  '1': 'EngineRemoveAccountRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineRemoveAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineRemoveAccountRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVSZW1vdmVBY2NvdW50UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQ=');

@$core.Deprecated('Use engineReorderAccountsRequestDescriptor instead')
const EngineReorderAccountsRequest$json = {
  '1': 'EngineReorderAccountsRequest',
  '2': [
    {'1': 'account_ids', '3': 1, '4': 3, '5': 9, '10': 'accountIds'},
  ],
};

/// Descriptor for `EngineReorderAccountsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineReorderAccountsRequestDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVSZW9yZGVyQWNjb3VudHNSZXF1ZXN0Eh8KC2FjY291bnRfaWRzGAEgAygJUgphY2'
    'NvdW50SWRz');

@$core.Deprecated('Use engineConnectAccountRequestDescriptor instead')
const EngineConnectAccountRequest$json = {
  '1': 'EngineConnectAccountRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineConnectAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineConnectAccountRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVDb25uZWN0QWNjb3VudFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElk');

@$core.Deprecated('Use engineDisconnectAccountRequestDescriptor instead')
const EngineDisconnectAccountRequest$json = {
  '1': 'EngineDisconnectAccountRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineDisconnectAccountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineDisconnectAccountRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVEaXNjb25uZWN0QWNjb3VudFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElk');

@$core.Deprecated('Use authOptionDescriptor instead')
const AuthOption$json = {
  '1': 'AuthOption',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'label', '3': 2, '4': 1, '5': 9, '10': 'label'},
  ],
};

/// Descriptor for `AuthOption`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authOptionDescriptor = $convert.base64Decode(
    'CgpBdXRoT3B0aW9uEg4KAmlkGAEgASgJUgJpZBIUCgVsYWJlbBgCIAEoCVIFbGFiZWw=');

@$core.Deprecated('Use engineAuthStateDescriptor instead')
const EngineAuthState$json = {
  '1': 'EngineAuthState',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'platform', '3': 2, '4': 1, '5': 9, '10': 'platform'},
    {'1': 'state', '3': 3, '4': 1, '5': 9, '10': 'state'},
    {'1': 'options', '3': 10, '4': 3, '5': 11, '6': '.uniclient.AuthOption', '10': 'options'},
    {'1': 'field_type', '3': 11, '4': 1, '5': 9, '10': 'fieldType'},
    {'1': 'label', '3': 12, '4': 1, '5': 9, '10': 'label'},
    {'1': 'hint', '3': 13, '4': 1, '5': 9, '10': 'hint'},
    {'1': 'error', '3': 14, '4': 1, '5': 9, '10': 'error'},
    {'1': 'code_length', '3': 15, '4': 1, '5': 5, '10': 'codeLength'},
    {'1': 'sent_to', '3': 16, '4': 1, '5': 9, '10': 'sentTo'},
    {'1': 'timeout_secs', '3': 17, '4': 1, '5': 5, '10': 'timeoutSecs'},
    {'1': 'can_resend', '3': 18, '4': 1, '5': 8, '10': 'canResend'},
    {'1': 'has_recovery', '3': 19, '4': 1, '5': 8, '10': 'hasRecovery'},
    {'1': 'qr_data', '3': 20, '4': 1, '5': 12, '10': 'qrData'},
    {'1': 'qr_expires_in', '3': 21, '4': 1, '5': 5, '10': 'qrExpiresIn'},
    {'1': 'display_name', '3': 22, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'avatar_b64', '3': 23, '4': 1, '5': 9, '10': 'avatarB64'},
    {'1': 'message', '3': 24, '4': 1, '5': 9, '10': 'message'},
    {'1': 'recoverable', '3': 25, '4': 1, '5': 8, '10': 'recoverable'},
  ],
};

/// Descriptor for `EngineAuthState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineAuthStateDescriptor = $convert.base64Decode(
    'Cg9FbmdpbmVBdXRoU3RhdGUSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudElkEhoKCHBsYX'
    'Rmb3JtGAIgASgJUghwbGF0Zm9ybRIUCgVzdGF0ZRgDIAEoCVIFc3RhdGUSLwoHb3B0aW9ucxgK'
    'IAMoCzIVLnVuaWNsaWVudC5BdXRoT3B0aW9uUgdvcHRpb25zEh0KCmZpZWxkX3R5cGUYCyABKA'
    'lSCWZpZWxkVHlwZRIUCgVsYWJlbBgMIAEoCVIFbGFiZWwSEgoEaGludBgNIAEoCVIEaGludBIU'
    'CgVlcnJvchgOIAEoCVIFZXJyb3ISHwoLY29kZV9sZW5ndGgYDyABKAVSCmNvZGVMZW5ndGgSFw'
    'oHc2VudF90bxgQIAEoCVIGc2VudFRvEiEKDHRpbWVvdXRfc2VjcxgRIAEoBVILdGltZW91dFNl'
    'Y3MSHQoKY2FuX3Jlc2VuZBgSIAEoCFIJY2FuUmVzZW5kEiEKDGhhc19yZWNvdmVyeRgTIAEoCF'
    'ILaGFzUmVjb3ZlcnkSFwoHcXJfZGF0YRgUIAEoDFIGcXJEYXRhEiIKDXFyX2V4cGlyZXNfaW4Y'
    'FSABKAVSC3FyRXhwaXJlc0luEiEKDGRpc3BsYXlfbmFtZRgWIAEoCVILZGlzcGxheU5hbWUSHQ'
    'oKYXZhdGFyX2I2NBgXIAEoCVIJYXZhdGFyQjY0EhgKB21lc3NhZ2UYGCABKAlSB21lc3NhZ2US'
    'IAoLcmVjb3ZlcmFibGUYGSABKAhSC3JlY292ZXJhYmxl');

@$core.Deprecated('Use engineStartAuthRequestDescriptor instead')
const EngineStartAuthRequest$json = {
  '1': 'EngineStartAuthRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineStartAuthRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineStartAuthRequestDescriptor = $convert.base64Decode(
    'ChZFbmdpbmVTdGFydEF1dGhSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bnRJZA'
    '==');

@$core.Deprecated('Use engineStartAuthResponseDescriptor instead')
const EngineStartAuthResponse$json = {
  '1': 'EngineStartAuthResponse',
  '2': [
    {'1': 'state', '3': 1, '4': 1, '5': 11, '6': '.uniclient.EngineAuthState', '10': 'state'},
  ],
};

/// Descriptor for `EngineStartAuthResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineStartAuthResponseDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVTdGFydEF1dGhSZXNwb25zZRIwCgVzdGF0ZRgBIAEoCzIaLnVuaWNsaWVudC5Fbm'
    'dpbmVBdXRoU3RhdGVSBXN0YXRl');

@$core.Deprecated('Use engineSubmitAuthInputRequestDescriptor instead')
const EngineSubmitAuthInputRequest$json = {
  '1': 'EngineSubmitAuthInputRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'input', '3': 2, '4': 1, '5': 9, '10': 'input'},
  ],
};

/// Descriptor for `EngineSubmitAuthInputRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSubmitAuthInputRequestDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVTdWJtaXRBdXRoSW5wdXRSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY2'
    '91bnRJZBIUCgVpbnB1dBgCIAEoCVIFaW5wdXQ=');

@$core.Deprecated('Use engineSubmitAuthInputResponseDescriptor instead')
const EngineSubmitAuthInputResponse$json = {
  '1': 'EngineSubmitAuthInputResponse',
  '2': [
    {'1': 'state', '3': 1, '4': 1, '5': 11, '6': '.uniclient.EngineAuthState', '10': 'state'},
  ],
};

/// Descriptor for `EngineSubmitAuthInputResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSubmitAuthInputResponseDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVTdWJtaXRBdXRoSW5wdXRSZXNwb25zZRIwCgVzdGF0ZRgBIAEoCzIaLnVuaWNsaW'
    'VudC5FbmdpbmVBdXRoU3RhdGVSBXN0YXRl');

@$core.Deprecated('Use engineCancelAuthRequestDescriptor instead')
const EngineCancelAuthRequest$json = {
  '1': 'EngineCancelAuthRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineCancelAuthRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCancelAuthRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVDYW5jZWxBdXRoUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'Q=');

@$core.Deprecated('Use engineChatInfoDescriptor instead')
const EngineChatInfo$json = {
  '1': 'EngineChatInfo',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'type', '3': 3, '4': 1, '5': 5, '10': 'type'},
    {'1': 'title', '3': 4, '4': 1, '5': 9, '10': 'title'},
    {'1': 'avatar_path', '3': 5, '4': 1, '5': 9, '10': 'avatarPath'},
    {'1': 'last_msg_id', '3': 6, '4': 1, '5': 9, '10': 'lastMsgId'},
    {'1': 'last_msg_text', '3': 7, '4': 1, '5': 9, '10': 'lastMsgText'},
    {'1': 'last_msg_time', '3': 8, '4': 1, '5': 3, '10': 'lastMsgTime'},
    {'1': 'last_msg_sender', '3': 9, '4': 1, '5': 9, '10': 'lastMsgSender'},
    {'1': 'last_msg_is_outgoing', '3': 17, '4': 1, '5': 8, '10': 'lastMsgIsOutgoing'},
    {'1': 'unread_count', '3': 10, '4': 1, '5': 5, '10': 'unreadCount'},
    {'1': 'is_muted', '3': 11, '4': 1, '5': 8, '10': 'isMuted'},
    {'1': 'is_pinned', '3': 12, '4': 1, '5': 8, '10': 'isPinned'},
    {'1': 'is_archived', '3': 13, '4': 1, '5': 8, '10': 'isArchived'},
    {'1': 'draft_text', '3': 14, '4': 1, '5': 9, '10': 'draftText'},
    {'1': 'member_count', '3': 15, '4': 1, '5': 5, '10': 'memberCount'},
    {'1': 'parent_id', '3': 16, '4': 1, '5': 9, '10': 'parentId'},
    {'1': 'is_bot', '3': 18, '4': 1, '5': 8, '10': 'isBot'},
    {'1': 'last_msg_status', '3': 19, '4': 1, '5': 5, '10': 'lastMsgStatus'},
    {'1': 'is_contact', '3': 20, '4': 1, '5': 8, '10': 'isContact'},
    {'1': 'is_blocked', '3': 21, '4': 1, '5': 8, '10': 'isBlocked'},
    {'1': 'slowmode_seconds', '3': 22, '4': 1, '5': 5, '10': 'slowmodeSeconds'},
    {'1': 'slowmode_next_send_date', '3': 23, '4': 1, '5': 3, '10': 'slowmodeNextSendDate'},
    {'1': 'stars_to_send', '3': 24, '4': 1, '5': 5, '10': 'starsToSend'},
    {'1': 'ttl_period', '3': 25, '4': 1, '5': 5, '10': 'ttlPeriod'},
    {'1': 'emoji_status_id', '3': 26, '4': 1, '5': 9, '10': 'emojiStatusId'},
    {'1': 'is_forum', '3': 27, '4': 1, '5': 8, '10': 'isForum'},
    {'1': 'write_restriction_type', '3': 28, '4': 1, '5': 5, '10': 'writeRestrictionType'},
    {'1': 'write_restriction_text', '3': 29, '4': 1, '5': 9, '10': 'writeRestrictionText'},
    {'1': 'not_joined', '3': 30, '4': 1, '5': 8, '10': 'notJoined'},
    {'1': 'join_request', '3': 31, '4': 1, '5': 8, '10': 'joinRequest'},
    {'1': 'can_post', '3': 32, '4': 1, '5': 8, '10': 'canPost'},
    {'1': 'no_forwards', '3': 33, '4': 1, '5': 8, '10': 'noForwards'},
    {'1': 'is_self', '3': 34, '4': 1, '5': 8, '10': 'isSelf'},
  ],
};

/// Descriptor for `EngineChatInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineChatInfoDescriptor = $convert.base64Decode(
    'Cg5FbmdpbmVDaGF0SW5mbxIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SWQSFwoHY2hhdF'
    '9pZBgCIAEoCVIGY2hhdElkEhIKBHR5cGUYAyABKAVSBHR5cGUSFAoFdGl0bGUYBCABKAlSBXRp'
    'dGxlEh8KC2F2YXRhcl9wYXRoGAUgASgJUgphdmF0YXJQYXRoEh4KC2xhc3RfbXNnX2lkGAYgAS'
    'gJUglsYXN0TXNnSWQSIgoNbGFzdF9tc2dfdGV4dBgHIAEoCVILbGFzdE1zZ1RleHQSIgoNbGFz'
    'dF9tc2dfdGltZRgIIAEoA1ILbGFzdE1zZ1RpbWUSJgoPbGFzdF9tc2dfc2VuZGVyGAkgASgJUg'
    '1sYXN0TXNnU2VuZGVyEi8KFGxhc3RfbXNnX2lzX291dGdvaW5nGBEgASgIUhFsYXN0TXNnSXNP'
    'dXRnb2luZxIhCgx1bnJlYWRfY291bnQYCiABKAVSC3VucmVhZENvdW50EhkKCGlzX211dGVkGA'
    'sgASgIUgdpc011dGVkEhsKCWlzX3Bpbm5lZBgMIAEoCFIIaXNQaW5uZWQSHwoLaXNfYXJjaGl2'
    'ZWQYDSABKAhSCmlzQXJjaGl2ZWQSHQoKZHJhZnRfdGV4dBgOIAEoCVIJZHJhZnRUZXh0EiEKDG'
    '1lbWJlcl9jb3VudBgPIAEoBVILbWVtYmVyQ291bnQSGwoJcGFyZW50X2lkGBAgASgJUghwYXJl'
    'bnRJZBIVCgZpc19ib3QYEiABKAhSBWlzQm90EiYKD2xhc3RfbXNnX3N0YXR1cxgTIAEoBVINbG'
    'FzdE1zZ1N0YXR1cxIdCgppc19jb250YWN0GBQgASgIUglpc0NvbnRhY3QSHQoKaXNfYmxvY2tl'
    'ZBgVIAEoCFIJaXNCbG9ja2VkEikKEHNsb3dtb2RlX3NlY29uZHMYFiABKAVSD3Nsb3dtb2RlU2'
    'Vjb25kcxI1ChdzbG93bW9kZV9uZXh0X3NlbmRfZGF0ZRgXIAEoA1IUc2xvd21vZGVOZXh0U2Vu'
    'ZERhdGUSIgoNc3RhcnNfdG9fc2VuZBgYIAEoBVILc3RhcnNUb1NlbmQSHQoKdHRsX3BlcmlvZB'
    'gZIAEoBVIJdHRsUGVyaW9kEiYKD2Vtb2ppX3N0YXR1c19pZBgaIAEoCVINZW1vamlTdGF0dXNJ'
    'ZBIZCghpc19mb3J1bRgbIAEoCFIHaXNGb3J1bRI0ChZ3cml0ZV9yZXN0cmljdGlvbl90eXBlGB'
    'wgASgFUhR3cml0ZVJlc3RyaWN0aW9uVHlwZRI0ChZ3cml0ZV9yZXN0cmljdGlvbl90ZXh0GB0g'
    'ASgJUhR3cml0ZVJlc3RyaWN0aW9uVGV4dBIdCgpub3Rfam9pbmVkGB4gASgIUglub3RKb2luZW'
    'QSIQoMam9pbl9yZXF1ZXN0GB8gASgIUgtqb2luUmVxdWVzdBIZCghjYW5fcG9zdBggIAEoCFIH'
    'Y2FuUG9zdBIfCgtub19mb3J3YXJkcxghIAEoCFIKbm9Gb3J3YXJkcxIXCgdpc19zZWxmGCIgAS'
    'gIUgZpc1NlbGY=');

@$core.Deprecated('Use engineGetChatListRequestDescriptor instead')
const EngineGetChatListRequest$json = {
  '1': 'EngineGetChatListRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'archived', '3': 2, '4': 1, '5': 8, '10': 'archived'},
    {'1': 'limit', '3': 3, '4': 1, '5': 5, '10': 'limit'},
    {'1': 'offset', '3': 4, '4': 1, '5': 5, '10': 'offset'},
  ],
};

/// Descriptor for `EngineGetChatListRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetChatListRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVHZXRDaGF0TGlzdFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhoKCGFyY2hpdmVkGAIgASgIUghhcmNoaXZlZBIUCgVsaW1pdBgDIAEoBVIFbGltaXQSFgoG'
    'b2Zmc2V0GAQgASgFUgZvZmZzZXQ=');

@$core.Deprecated('Use engineGetChatListResponseDescriptor instead')
const EngineGetChatListResponse$json = {
  '1': 'EngineGetChatListResponse',
  '2': [
    {'1': 'chats', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineChatInfo', '10': 'chats'},
  ],
};

/// Descriptor for `EngineGetChatListResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetChatListResponseDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVHZXRDaGF0TGlzdFJlc3BvbnNlEi8KBWNoYXRzGAEgAygLMhkudW5pY2xpZW50Lk'
    'VuZ2luZUNoYXRJbmZvUgVjaGF0cw==');

@$core.Deprecated('Use engineSaveDraftRequestDescriptor instead')
const EngineSaveDraftRequest$json = {
  '1': 'EngineSaveDraftRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'text', '3': 3, '4': 1, '5': 9, '10': 'text'},
  ],
};

/// Descriptor for `EngineSaveDraftRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSaveDraftRequestDescriptor = $convert.base64Decode(
    'ChZFbmdpbmVTYXZlRHJhZnRSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bnRJZB'
    'IXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSEgoEdGV4dBgDIAEoCVIEdGV4dA==');

@$core.Deprecated('Use engineMuteChatRequestDescriptor instead')
const EngineMuteChatRequest$json = {
  '1': 'EngineMuteChatRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'muted', '3': 3, '4': 1, '5': 8, '10': 'muted'},
    {'1': 'duration_seconds', '3': 4, '4': 1, '5': 5, '10': 'durationSeconds'},
  ],
};

/// Descriptor for `EngineMuteChatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineMuteChatRequestDescriptor = $convert.base64Decode(
    'ChVFbmdpbmVNdXRlQ2hhdFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudElkEh'
    'cKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIUCgVtdXRlZBgDIAEoCFIFbXV0ZWQSKQoQZHVyYXRp'
    'b25fc2Vjb25kcxgEIAEoBVIPZHVyYXRpb25TZWNvbmRz');

@$core.Deprecated('Use enginePinChatRequestDescriptor instead')
const EnginePinChatRequest$json = {
  '1': 'EnginePinChatRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'pinned', '3': 3, '4': 1, '5': 8, '10': 'pinned'},
  ],
};

/// Descriptor for `EnginePinChatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List enginePinChatRequestDescriptor = $convert.base64Decode(
    'ChRFbmdpbmVQaW5DaGF0UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SWQSFw'
    'oHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhYKBnBpbm5lZBgDIAEoCFIGcGlubmVk');

@$core.Deprecated('Use engineArchiveChatRequestDescriptor instead')
const EngineArchiveChatRequest$json = {
  '1': 'EngineArchiveChatRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'archived', '3': 3, '4': 1, '5': 8, '10': 'archived'},
  ],
};

/// Descriptor for `EngineArchiveChatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineArchiveChatRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVBcmNoaXZlQ2hhdFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIaCghhcmNoaXZlZBgDIAEoCFIIYXJjaGl2ZWQ=');

@$core.Deprecated('Use engineSetHistoryTTLRequestDescriptor instead')
const EngineSetHistoryTTLRequest$json = {
  '1': 'EngineSetHistoryTTLRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'period', '3': 3, '4': 1, '5': 5, '10': 'period'},
  ],
};

/// Descriptor for `EngineSetHistoryTTLRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSetHistoryTTLRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVTZXRIaXN0b3J5VFRMUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhYKBnBlcmlvZBgDIAEoBVIGcGVyaW9k');

@$core.Deprecated('Use engineMarkChatReadRequestDescriptor instead')
const EngineMarkChatReadRequest$json = {
  '1': 'EngineMarkChatReadRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'up_to_msg_id', '3': 3, '4': 1, '5': 9, '10': 'upToMsgId'},
  ],
};

/// Descriptor for `EngineMarkChatReadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineMarkChatReadRequestDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVNYXJrQ2hhdFJlYWRSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bn'
    'RJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSHwoMdXBfdG9fbXNnX2lkGAMgASgJUgl1cFRv'
    'TXNnSWQ=');

@$core.Deprecated('Use engineBlockUserRequestDescriptor instead')
const EngineBlockUserRequest$json = {
  '1': 'EngineBlockUserRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `EngineBlockUserRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineBlockUserRequestDescriptor = $convert.base64Decode(
    'ChZFbmdpbmVCbG9ja1VzZXJSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bnRJZB'
    'IXCgd1c2VyX2lkGAIgASgJUgZ1c2VySWQ=');

@$core.Deprecated('Use engineUnblockUserRequestDescriptor instead')
const EngineUnblockUserRequest$json = {
  '1': 'EngineUnblockUserRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `EngineUnblockUserRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineUnblockUserRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVVbmJsb2NrVXNlclJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB3VzZXJfaWQYAiABKAlSBnVzZXJJZA==');

@$core.Deprecated('Use engineAddContactRequestDescriptor instead')
const EngineAddContactRequest$json = {
  '1': 'EngineAddContactRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'phone', '3': 2, '4': 1, '5': 9, '10': 'phone'},
    {'1': 'first_name', '3': 3, '4': 1, '5': 9, '10': 'firstName'},
    {'1': 'last_name', '3': 4, '4': 1, '5': 9, '10': 'lastName'},
    {'1': 'note', '3': 5, '4': 1, '5': 9, '10': 'note'},
  ],
};

/// Descriptor for `EngineAddContactRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineAddContactRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVBZGRDb250YWN0UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'QSFAoFcGhvbmUYAiABKAlSBXBob25lEh0KCmZpcnN0X25hbWUYAyABKAlSCWZpcnN0TmFtZRIb'
    'CglsYXN0X25hbWUYBCABKAlSCGxhc3ROYW1lEhIKBG5vdGUYBSABKAlSBG5vdGU=');

@$core.Deprecated('Use engineGetForumTopicsRequestDescriptor instead')
const EngineGetForumTopicsRequest$json = {
  '1': 'EngineGetForumTopicsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineGetForumTopicsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetForumTopicsRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVHZXRGb3J1bVRvcGljc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZA==');

@$core.Deprecated('Use engineForumTopicDescriptor instead')
const EngineForumTopic$json = {
  '1': 'EngineForumTopic',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'color_id', '3': 3, '4': 1, '5': 5, '10': 'colorId'},
    {'1': 'icon_emoji_id', '3': 4, '4': 1, '5': 3, '10': 'iconEmojiId'},
    {'1': 'creator_id', '3': 5, '4': 1, '5': 9, '10': 'creatorId'},
    {'1': 'creation_date', '3': 6, '4': 1, '5': 3, '10': 'creationDate'},
    {'1': 'is_closed', '3': 7, '4': 1, '5': 8, '10': 'isClosed'},
    {'1': 'is_hidden', '3': 8, '4': 1, '5': 8, '10': 'isHidden'},
    {'1': 'is_my', '3': 9, '4': 1, '5': 8, '10': 'isMy'},
    {'1': 'is_pinned', '3': 10, '4': 1, '5': 8, '10': 'isPinned'},
    {'1': 'unread_count', '3': 11, '4': 1, '5': 5, '10': 'unreadCount'},
    {'1': 'unread_mentions', '3': 12, '4': 1, '5': 5, '10': 'unreadMentions'},
    {'1': 'unread_reactions', '3': 13, '4': 1, '5': 5, '10': 'unreadReactions'},
    {'1': 'top_message_id', '3': 14, '4': 1, '5': 9, '10': 'topMessageId'},
    {'1': 'read_inbox_max_id', '3': 15, '4': 1, '5': 5, '10': 'readInboxMaxId'},
    {'1': 'read_outbox_max_id', '3': 16, '4': 1, '5': 5, '10': 'readOutboxMaxId'},
    {'1': 'parent_id', '3': 17, '4': 1, '5': 9, '10': 'parentId'},
    {'1': 'can_edit', '3': 18, '4': 1, '5': 8, '10': 'canEdit'},
    {'1': 'can_delete', '3': 19, '4': 1, '5': 8, '10': 'canDelete'},
    {'1': 'can_toggle_closed', '3': 20, '4': 1, '5': 8, '10': 'canToggleClosed'},
    {'1': 'can_toggle_pinned', '3': 21, '4': 1, '5': 8, '10': 'canTogglePinned'},
  ],
};

/// Descriptor for `EngineForumTopic`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineForumTopicDescriptor = $convert.base64Decode(
    'ChBFbmdpbmVGb3J1bVRvcGljEg4KAmlkGAEgASgJUgJpZBIUCgV0aXRsZRgCIAEoCVIFdGl0bG'
    'USGQoIY29sb3JfaWQYAyABKAVSB2NvbG9ySWQSIgoNaWNvbl9lbW9qaV9pZBgEIAEoA1ILaWNv'
    'bkVtb2ppSWQSHQoKY3JlYXRvcl9pZBgFIAEoCVIJY3JlYXRvcklkEiMKDWNyZWF0aW9uX2RhdG'
    'UYBiABKANSDGNyZWF0aW9uRGF0ZRIbCglpc19jbG9zZWQYByABKAhSCGlzQ2xvc2VkEhsKCWlz'
    'X2hpZGRlbhgIIAEoCFIIaXNIaWRkZW4SEwoFaXNfbXkYCSABKAhSBGlzTXkSGwoJaXNfcGlubm'
    'VkGAogASgIUghpc1Bpbm5lZBIhCgx1bnJlYWRfY291bnQYCyABKAVSC3VucmVhZENvdW50EicK'
    'D3VucmVhZF9tZW50aW9ucxgMIAEoBVIOdW5yZWFkTWVudGlvbnMSKQoQdW5yZWFkX3JlYWN0aW'
    '9ucxgNIAEoBVIPdW5yZWFkUmVhY3Rpb25zEiQKDnRvcF9tZXNzYWdlX2lkGA4gASgJUgx0b3BN'
    'ZXNzYWdlSWQSKQoRcmVhZF9pbmJveF9tYXhfaWQYDyABKAVSDnJlYWRJbmJveE1heElkEisKEn'
    'JlYWRfb3V0Ym94X21heF9pZBgQIAEoBVIPcmVhZE91dGJveE1heElkEhsKCXBhcmVudF9pZBgR'
    'IAEoCVIIcGFyZW50SWQSGQoIY2FuX2VkaXQYEiABKAhSB2NhbkVkaXQSHQoKY2FuX2RlbGV0ZR'
    'gTIAEoCFIJY2FuRGVsZXRlEioKEWNhbl90b2dnbGVfY2xvc2VkGBQgASgIUg9jYW5Ub2dnbGVD'
    'bG9zZWQSKgoRY2FuX3RvZ2dsZV9waW5uZWQYFSABKAhSD2NhblRvZ2dsZVBpbm5lZA==');

@$core.Deprecated('Use engineGetForumTopicsResponseDescriptor instead')
const EngineGetForumTopicsResponse$json = {
  '1': 'EngineGetForumTopicsResponse',
  '2': [
    {'1': 'topics', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineForumTopic', '10': 'topics'},
  ],
};

/// Descriptor for `EngineGetForumTopicsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetForumTopicsResponseDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVHZXRGb3J1bVRvcGljc1Jlc3BvbnNlEjMKBnRvcGljcxgBIAMoCzIbLnVuaWNsaW'
    'VudC5FbmdpbmVGb3J1bVRvcGljUgZ0b3BpY3M=');

@$core.Deprecated('Use engineCreateForumTopicRequestDescriptor instead')
const EngineCreateForumTopicRequest$json = {
  '1': 'EngineCreateForumTopicRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {'1': 'color_id', '3': 4, '4': 1, '5': 5, '10': 'colorId'},
    {'1': 'icon_emoji_id', '3': 5, '4': 1, '5': 3, '10': 'iconEmojiId'},
  ],
};

/// Descriptor for `EngineCreateForumTopicRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCreateForumTopicRequestDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVDcmVhdGVGb3J1bVRvcGljUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2'
    'NvdW50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhQKBXRpdGxlGAMgASgJUgV0aXRsZRIZ'
    'Cghjb2xvcl9pZBgEIAEoBVIHY29sb3JJZBIiCg1pY29uX2Vtb2ppX2lkGAUgASgDUgtpY29uRW'
    '1vamlJZA==');

@$core.Deprecated('Use engineCreateForumTopicResponseDescriptor instead')
const EngineCreateForumTopicResponse$json = {
  '1': 'EngineCreateForumTopicResponse',
  '2': [
    {'1': 'topic_id', '3': 1, '4': 1, '5': 3, '10': 'topicId'},
  ],
};

/// Descriptor for `EngineCreateForumTopicResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCreateForumTopicResponseDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVDcmVhdGVGb3J1bVRvcGljUmVzcG9uc2USGQoIdG9waWNfaWQYASABKANSB3RvcG'
    'ljSWQ=');

@$core.Deprecated('Use engineEditForumTopicRequestDescriptor instead')
const EngineEditForumTopicRequest$json = {
  '1': 'EngineEditForumTopicRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'topic_id', '3': 3, '4': 1, '5': 3, '10': 'topicId'},
    {'1': 'title', '3': 4, '4': 1, '5': 9, '10': 'title'},
    {'1': 'color_id', '3': 5, '4': 1, '5': 5, '10': 'colorId'},
    {'1': 'icon_emoji_id', '3': 6, '4': 1, '5': 3, '10': 'iconEmojiId'},
  ],
};

/// Descriptor for `EngineEditForumTopicRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineEditForumTopicRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVFZGl0Rm9ydW1Ub3BpY1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIZCgh0b3BpY19pZBgDIAEoA1IHdG9waWNJ'
    'ZBIUCgV0aXRsZRgEIAEoCVIFdGl0bGUSGQoIY29sb3JfaWQYBSABKAVSB2NvbG9ySWQSIgoNaW'
    'Nvbl9lbW9qaV9pZBgGIAEoA1ILaWNvbkVtb2ppSWQ=');

@$core.Deprecated('Use engineCachedMessageDescriptor instead')
const EngineCachedMessage$json = {
  '1': 'EngineCachedMessage',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'local_id', '3': 4, '4': 1, '5': 9, '10': 'localId'},
    {'1': 'sender_id', '3': 5, '4': 1, '5': 9, '10': 'senderId'},
    {'1': 'sender_name', '3': 6, '4': 1, '5': 9, '10': 'senderName'},
    {'1': 'content_text', '3': 7, '4': 1, '5': 9, '10': 'contentText'},
    {'1': 'content_raw', '3': 8, '4': 1, '5': 12, '10': 'contentRaw'},
    {'1': 'content_rich', '3': 9, '4': 1, '5': 12, '10': 'contentRich'},
    {'1': 'timestamp', '3': 10, '4': 1, '5': 3, '10': 'timestamp'},
    {'1': 'edited_at', '3': 11, '4': 1, '5': 3, '10': 'editedAt'},
    {'1': 'status', '3': 12, '4': 1, '5': 5, '10': 'status'},
    {'1': 'reply_to_id', '3': 13, '4': 1, '5': 9, '10': 'replyToId'},
    {'1': 'reply_preview', '3': 14, '4': 1, '5': 9, '10': 'replyPreview'},
    {'1': 'forward_from', '3': 15, '4': 1, '5': 9, '10': 'forwardFrom'},
    {'1': 'is_pinned', '3': 16, '4': 1, '5': 8, '10': 'isPinned'},
    {'1': 'has_media', '3': 17, '4': 1, '5': 8, '10': 'hasMedia'},
    {'1': 'media_type', '3': 18, '4': 1, '5': 5, '10': 'mediaType'},
    {'1': 'media_file_name', '3': 19, '4': 1, '5': 9, '10': 'mediaFileName'},
    {'1': 'media_mime_type', '3': 20, '4': 1, '5': 9, '10': 'mediaMimeType'},
    {'1': 'media_file_size', '3': 21, '4': 1, '5': 3, '10': 'mediaFileSize'},
    {'1': 'media_thumb_b64', '3': 22, '4': 1, '5': 9, '10': 'mediaThumbB64'},
    {'1': 'media_local_path', '3': 23, '4': 1, '5': 9, '10': 'mediaLocalPath'},
    {'1': 'media_width', '3': 24, '4': 1, '5': 5, '10': 'mediaWidth'},
    {'1': 'media_height', '3': 25, '4': 1, '5': 5, '10': 'mediaHeight'},
    {'1': 'media_duration', '3': 26, '4': 1, '5': 5, '10': 'mediaDuration'},
    {'1': 'media_download_state', '3': 27, '4': 1, '5': 5, '10': 'mediaDownloadState'},
    {'1': 'is_outgoing', '3': 28, '4': 1, '5': 8, '10': 'isOutgoing'},
    {'1': 'sender_rank', '3': 29, '4': 1, '5': 9, '10': 'senderRank'},
    {'1': 'sender_color_id', '3': 30, '4': 1, '5': 5, '10': 'senderColorId'},
    {'1': 'is_service', '3': 31, '4': 1, '5': 8, '10': 'isService'},
    {'1': 'grouped_id', '3': 32, '4': 1, '5': 9, '10': 'groupedId'},
    {'1': 'media_remote_ref', '3': 33, '4': 1, '5': 9, '10': 'mediaRemoteRef'},
    {'1': 'media_extra', '3': 34, '4': 1, '5': 9, '10': 'mediaExtra'},
    {'1': 'sender_no_forwards', '3': 35, '4': 1, '5': 8, '10': 'senderNoForwards'},
  ],
};

/// Descriptor for `EngineCachedMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCachedMessageDescriptor = $convert.base64Decode(
    'ChNFbmdpbmVDYWNoZWRNZXNzYWdlEh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bnRJZBIXCg'
    'djaGF0X2lkGAIgASgJUgZjaGF0SWQSFQoGbXNnX2lkGAMgASgJUgVtc2dJZBIZCghsb2NhbF9p'
    'ZBgEIAEoCVIHbG9jYWxJZBIbCglzZW5kZXJfaWQYBSABKAlSCHNlbmRlcklkEh8KC3NlbmRlcl'
    '9uYW1lGAYgASgJUgpzZW5kZXJOYW1lEiEKDGNvbnRlbnRfdGV4dBgHIAEoCVILY29udGVudFRl'
    'eHQSHwoLY29udGVudF9yYXcYCCABKAxSCmNvbnRlbnRSYXcSIQoMY29udGVudF9yaWNoGAkgAS'
    'gMUgtjb250ZW50UmljaBIcCgl0aW1lc3RhbXAYCiABKANSCXRpbWVzdGFtcBIbCgllZGl0ZWRf'
    'YXQYCyABKANSCGVkaXRlZEF0EhYKBnN0YXR1cxgMIAEoBVIGc3RhdHVzEh4KC3JlcGx5X3RvX2'
    'lkGA0gASgJUglyZXBseVRvSWQSIwoNcmVwbHlfcHJldmlldxgOIAEoCVIMcmVwbHlQcmV2aWV3'
    'EiEKDGZvcndhcmRfZnJvbRgPIAEoCVILZm9yd2FyZEZyb20SGwoJaXNfcGlubmVkGBAgASgIUg'
    'hpc1Bpbm5lZBIbCgloYXNfbWVkaWEYESABKAhSCGhhc01lZGlhEh0KCm1lZGlhX3R5cGUYEiAB'
    'KAVSCW1lZGlhVHlwZRImCg9tZWRpYV9maWxlX25hbWUYEyABKAlSDW1lZGlhRmlsZU5hbWUSJg'
    'oPbWVkaWFfbWltZV90eXBlGBQgASgJUg1tZWRpYU1pbWVUeXBlEiYKD21lZGlhX2ZpbGVfc2l6'
    'ZRgVIAEoA1INbWVkaWFGaWxlU2l6ZRImCg9tZWRpYV90aHVtYl9iNjQYFiABKAlSDW1lZGlhVG'
    'h1bWJCNjQSKAoQbWVkaWFfbG9jYWxfcGF0aBgXIAEoCVIObWVkaWFMb2NhbFBhdGgSHwoLbWVk'
    'aWFfd2lkdGgYGCABKAVSCm1lZGlhV2lkdGgSIQoMbWVkaWFfaGVpZ2h0GBkgASgFUgttZWRpYU'
    'hlaWdodBIlCg5tZWRpYV9kdXJhdGlvbhgaIAEoBVINbWVkaWFEdXJhdGlvbhIwChRtZWRpYV9k'
    'b3dubG9hZF9zdGF0ZRgbIAEoBVISbWVkaWFEb3dubG9hZFN0YXRlEh8KC2lzX291dGdvaW5nGB'
    'wgASgIUgppc091dGdvaW5nEh8KC3NlbmRlcl9yYW5rGB0gASgJUgpzZW5kZXJSYW5rEiYKD3Nl'
    'bmRlcl9jb2xvcl9pZBgeIAEoBVINc2VuZGVyQ29sb3JJZBIdCgppc19zZXJ2aWNlGB8gASgIUg'
    'lpc1NlcnZpY2USHQoKZ3JvdXBlZF9pZBggIAEoCVIJZ3JvdXBlZElkEigKEG1lZGlhX3JlbW90'
    'ZV9yZWYYISABKAlSDm1lZGlhUmVtb3RlUmVmEh8KC21lZGlhX2V4dHJhGCIgASgJUgptZWRpYU'
    'V4dHJhEiwKEnNlbmRlcl9ub19mb3J3YXJkcxgjIAEoCFIQc2VuZGVyTm9Gb3J3YXJkcw==');

@$core.Deprecated('Use engineGetMessagesRequestDescriptor instead')
const EngineGetMessagesRequest$json = {
  '1': 'EngineGetMessagesRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'before_ms', '3': 3, '4': 1, '5': 3, '10': 'beforeMs'},
    {'1': 'limit', '3': 4, '4': 1, '5': 5, '10': 'limit'},
  ],
};

/// Descriptor for `EngineGetMessagesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetMessagesRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVHZXRNZXNzYWdlc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIbCgliZWZvcmVfbXMYAyABKANSCGJlZm9yZU1z'
    'EhQKBWxpbWl0GAQgASgFUgVsaW1pdA==');

@$core.Deprecated('Use engineGetMessagesResponseDescriptor instead')
const EngineGetMessagesResponse$json = {
  '1': 'EngineGetMessagesResponse',
  '2': [
    {'1': 'messages', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineCachedMessage', '10': 'messages'},
  ],
};

/// Descriptor for `EngineGetMessagesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetMessagesResponseDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVHZXRNZXNzYWdlc1Jlc3BvbnNlEjoKCG1lc3NhZ2VzGAEgAygLMh4udW5pY2xpZW'
    '50LkVuZ2luZUNhY2hlZE1lc3NhZ2VSCG1lc3NhZ2Vz');

@$core.Deprecated('Use engineSendMessageRequestDescriptor instead')
const EngineSendMessageRequest$json = {
  '1': 'EngineSendMessageRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'text', '3': 3, '4': 1, '5': 9, '10': 'text'},
    {'1': 'reply_to_id', '3': 4, '4': 1, '5': 9, '10': 'replyToId'},
    {'1': 'silent', '3': 5, '4': 1, '5': 8, '10': 'silent'},
    {'1': 'schedule_date', '3': 6, '4': 1, '5': 3, '10': 'scheduleDate'},
    {'1': 'topic_root_id', '3': 7, '4': 1, '5': 9, '10': 'topicRootId'},
    {'1': 'entities_json', '3': 8, '4': 1, '5': 9, '10': 'entitiesJson'},
    {'1': 'web_page_url', '3': 9, '4': 1, '5': 9, '10': 'webPageUrl'},
    {'1': 'force_large_media', '3': 10, '4': 1, '5': 8, '10': 'forceLargeMedia'},
    {'1': 'force_small_media', '3': 11, '4': 1, '5': 8, '10': 'forceSmallMedia'},
    {'1': 'invert_media', '3': 12, '4': 1, '5': 8, '10': 'invertMedia'},
    {'1': 'web_page_optional', '3': 13, '4': 1, '5': 8, '10': 'webPageOptional'},
  ],
};

/// Descriptor for `EngineSendMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSendMessageRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVTZW5kTWVzc2FnZVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBISCgR0ZXh0GAMgASgJUgR0ZXh0Eh4KC3JlcGx5'
    'X3RvX2lkGAQgASgJUglyZXBseVRvSWQSFgoGc2lsZW50GAUgASgIUgZzaWxlbnQSIwoNc2NoZW'
    'R1bGVfZGF0ZRgGIAEoA1IMc2NoZWR1bGVEYXRlEiIKDXRvcGljX3Jvb3RfaWQYByABKAlSC3Rv'
    'cGljUm9vdElkEiMKDWVudGl0aWVzX2pzb24YCCABKAlSDGVudGl0aWVzSnNvbhIgCgx3ZWJfcG'
    'FnZV91cmwYCSABKAlSCndlYlBhZ2VVcmwSKgoRZm9yY2VfbGFyZ2VfbWVkaWEYCiABKAhSD2Zv'
    'cmNlTGFyZ2VNZWRpYRIqChFmb3JjZV9zbWFsbF9tZWRpYRgLIAEoCFIPZm9yY2VTbWFsbE1lZG'
    'lhEiEKDGludmVydF9tZWRpYRgMIAEoCFILaW52ZXJ0TWVkaWESKgoRd2ViX3BhZ2Vfb3B0aW9u'
    'YWwYDSABKAhSD3dlYlBhZ2VPcHRpb25hbA==');

@$core.Deprecated('Use engineSendMessageResponseDescriptor instead')
const EngineSendMessageResponse$json = {
  '1': 'EngineSendMessageResponse',
  '2': [
    {'1': 'local_id', '3': 1, '4': 1, '5': 9, '10': 'localId'},
  ],
};

/// Descriptor for `EngineSendMessageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSendMessageResponseDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVTZW5kTWVzc2FnZVJlc3BvbnNlEhkKCGxvY2FsX2lkGAEgASgJUgdsb2NhbElk');

@$core.Deprecated('Use engineEditMessageRequestDescriptor instead')
const EngineEditMessageRequest$json = {
  '1': 'EngineEditMessageRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'new_text', '3': 4, '4': 1, '5': 9, '10': 'newText'},
    {'1': 'entities_json', '3': 5, '4': 1, '5': 9, '10': 'entitiesJson'},
  ],
};

/// Descriptor for `EngineEditMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineEditMessageRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVFZGl0TWVzc2FnZVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lkEhkKCG5l'
    'd190ZXh0GAQgASgJUgduZXdUZXh0EiMKDWVudGl0aWVzX2pzb24YBSABKAlSDGVudGl0aWVzSn'
    'Nvbg==');

@$core.Deprecated('Use engineDeleteMessageRequestDescriptor instead')
const EngineDeleteMessageRequest$json = {
  '1': 'EngineDeleteMessageRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
  ],
};

/// Descriptor for `EngineDeleteMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineDeleteMessageRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVEZWxldGVNZXNzYWdlUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhUKBm1zZ19pZBgDIAEoCVIFbXNnSWQ=');

@$core.Deprecated('Use engineJoinChatRequestDescriptor instead')
const EngineJoinChatRequest$json = {
  '1': 'EngineJoinChatRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'channel_name', '3': 2, '4': 1, '5': 9, '10': 'channelName'},
  ],
};

/// Descriptor for `EngineJoinChatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineJoinChatRequestDescriptor = $convert.base64Decode(
    'ChVFbmdpbmVKb2luQ2hhdFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudElkEi'
    'EKDGNoYW5uZWxfbmFtZRgCIAEoCVILY2hhbm5lbE5hbWU=');

@$core.Deprecated('Use engineLeaveChatRequestDescriptor instead')
const EngineLeaveChatRequest$json = {
  '1': 'EngineLeaveChatRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineLeaveChatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineLeaveChatRequestDescriptor = $convert.base64Decode(
    'ChZFbmdpbmVMZWF2ZUNoYXRSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bnRJZB'
    'IXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQ=');

@$core.Deprecated('Use engineReportSpamRequestDescriptor instead')
const EngineReportSpamRequest$json = {
  '1': 'EngineReportSpamRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineReportSpamRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineReportSpamRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVSZXBvcnRTcGFtUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'QSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElk');

@$core.Deprecated('Use engineGetLinkedChatIdRequestDescriptor instead')
const EngineGetLinkedChatIdRequest$json = {
  '1': 'EngineGetLinkedChatIdRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineGetLinkedChatIdRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetLinkedChatIdRequestDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVHZXRMaW5rZWRDaGF0SWRSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY2'
    '91bnRJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQ=');

@$core.Deprecated('Use engineDeleteContactRequestDescriptor instead')
const EngineDeleteContactRequest$json = {
  '1': 'EngineDeleteContactRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `EngineDeleteContactRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineDeleteContactRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVEZWxldGVDb250YWN0UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHdXNlcl9pZBgCIAEoCVIGdXNlcklk');

@$core.Deprecated('Use engineJoinChannelRequestDescriptor instead')
const EngineJoinChannelRequest$json = {
  '1': 'EngineJoinChannelRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineJoinChannelRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineJoinChannelRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVKb2luQ2hhbm5lbFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZA==');

@$core.Deprecated('Use engineEditChatTitleRequestDescriptor instead')
const EngineEditChatTitleRequest$json = {
  '1': 'EngineEditChatTitleRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
  ],
};

/// Descriptor for `EngineEditChatTitleRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineEditChatTitleRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVFZGl0Q2hhdFRpdGxlUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhQKBXRpdGxlGAMgASgJUgV0aXRsZQ==');

@$core.Deprecated('Use engineEditChatDescriptionRequestDescriptor instead')
const EngineEditChatDescriptionRequest$json = {
  '1': 'EngineEditChatDescriptionRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `EngineEditChatDescriptionRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineEditChatDescriptionRequestDescriptor = $convert.base64Decode(
    'CiBFbmdpbmVFZGl0Q2hhdERlc2NyaXB0aW9uUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUg'
    'lhY2NvdW50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEiAKC2Rlc2NyaXB0aW9uGAMgASgJ'
    'UgtkZXNjcmlwdGlvbg==');

@$core.Deprecated('Use engineToggleForumRequestDescriptor instead')
const EngineToggleForumRequest$json = {
  '1': 'EngineToggleForumRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'enabled', '3': 3, '4': 1, '5': 8, '10': 'enabled'},
  ],
};

/// Descriptor for `EngineToggleForumRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineToggleForumRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVUb2dnbGVGb3J1bVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIYCgdlbmFibGVkGAMgASgIUgdlbmFibGVk');

@$core.Deprecated('Use engineClearHistoryRequestDescriptor instead')
const EngineClearHistoryRequest$json = {
  '1': 'EngineClearHistoryRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineClearHistoryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineClearHistoryRequestDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVDbGVhckhpc3RvcnlSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bn'
    'RJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQ=');

@$core.Deprecated('Use engineDeleteChatRequestDescriptor instead')
const EngineDeleteChatRequest$json = {
  '1': 'EngineDeleteChatRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineDeleteChatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineDeleteChatRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVEZWxldGVDaGF0UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'QSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElk');

@$core.Deprecated('Use engineReadMessageContentsRequestDescriptor instead')
const EngineReadMessageContentsRequest$json = {
  '1': 'EngineReadMessageContentsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
  ],
};

/// Descriptor for `EngineReadMessageContentsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineReadMessageContentsRequestDescriptor = $convert.base64Decode(
    'CiBFbmdpbmVSZWFkTWVzc2FnZUNvbnRlbnRzUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUg'
    'lhY2NvdW50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhUKBm1zZ19pZBgDIAEoCVIFbXNn'
    'SWQ=');

@$core.Deprecated('Use enginePinForumTopicRequestDescriptor instead')
const EnginePinForumTopicRequest$json = {
  '1': 'EnginePinForumTopicRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'topic_id', '3': 3, '4': 1, '5': 3, '10': 'topicId'},
    {'1': 'pinned', '3': 4, '4': 1, '5': 8, '10': 'pinned'},
  ],
};

/// Descriptor for `EnginePinForumTopicRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List enginePinForumTopicRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVQaW5Gb3J1bVRvcGljUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhkKCHRvcGljX2lkGAMgASgDUgd0b3BpY0lk'
    'EhYKBnBpbm5lZBgEIAEoCFIGcGlubmVk');

@$core.Deprecated('Use engineToggleForumTopicClosedRequestDescriptor instead')
const EngineToggleForumTopicClosedRequest$json = {
  '1': 'EngineToggleForumTopicClosedRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'topic_id', '3': 3, '4': 1, '5': 3, '10': 'topicId'},
    {'1': 'closed', '3': 4, '4': 1, '5': 8, '10': 'closed'},
  ],
};

/// Descriptor for `EngineToggleForumTopicClosedRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineToggleForumTopicClosedRequestDescriptor = $convert.base64Decode(
    'CiNFbmdpbmVUb2dnbGVGb3J1bVRvcGljQ2xvc2VkUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgAS'
    'gJUglhY2NvdW50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhkKCHRvcGljX2lkGAMgASgD'
    'Ugd0b3BpY0lkEhYKBmNsb3NlZBgEIAEoCFIGY2xvc2Vk');

@$core.Deprecated('Use engineToggleGeneralTopicHiddenRequestDescriptor instead')
const EngineToggleGeneralTopicHiddenRequest$json = {
  '1': 'EngineToggleGeneralTopicHiddenRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'hidden', '3': 3, '4': 1, '5': 8, '10': 'hidden'},
  ],
};

/// Descriptor for `EngineToggleGeneralTopicHiddenRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineToggleGeneralTopicHiddenRequestDescriptor = $convert.base64Decode(
    'CiVFbmdpbmVUb2dnbGVHZW5lcmFsVG9waWNIaWRkZW5SZXF1ZXN0Eh0KCmFjY291bnRfaWQYAS'
    'ABKAlSCWFjY291bnRJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSFgoGaGlkZGVuGAMgASgI'
    'UgZoaWRkZW4=');

@$core.Deprecated('Use engineMarkSavedSublistReadRequestDescriptor instead')
const EngineMarkSavedSublistReadRequest$json = {
  '1': 'EngineMarkSavedSublistReadRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'peer_id', '3': 2, '4': 1, '5': 9, '10': 'peerId'},
  ],
};

/// Descriptor for `EngineMarkSavedSublistReadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineMarkSavedSublistReadRequestDescriptor = $convert.base64Decode(
    'CiFFbmdpbmVNYXJrU2F2ZWRTdWJsaXN0UmVhZFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCV'
    'IJYWNjb3VudElkEhcKB3BlZXJfaWQYAiABKAlSBnBlZXJJZA==');

@$core.Deprecated('Use engineDeleteSavedSublistHistoryRequestDescriptor instead')
const EngineDeleteSavedSublistHistoryRequest$json = {
  '1': 'EngineDeleteSavedSublistHistoryRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'peer_id', '3': 2, '4': 1, '5': 9, '10': 'peerId'},
  ],
};

/// Descriptor for `EngineDeleteSavedSublistHistoryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineDeleteSavedSublistHistoryRequestDescriptor = $convert.base64Decode(
    'CiZFbmdpbmVEZWxldGVTYXZlZFN1Ymxpc3RIaXN0b3J5UmVxdWVzdBIdCgphY2NvdW50X2lkGA'
    'EgASgJUglhY2NvdW50SWQSFwoHcGVlcl9pZBgCIAEoCVIGcGVlcklk');

@$core.Deprecated('Use engineForwardMessageRequestDescriptor instead')
const EngineForwardMessageRequest$json = {
  '1': 'EngineForwardMessageRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'to_chat_id', '3': 4, '4': 1, '5': 9, '10': 'toChatId'},
    {'1': 'drop_author', '3': 5, '4': 1, '5': 8, '10': 'dropAuthor'},
    {'1': 'drop_captions', '3': 6, '4': 1, '5': 8, '10': 'dropCaptions'},
    {'1': 'silent', '3': 7, '4': 1, '5': 8, '10': 'silent'},
    {'1': 'schedule_date', '3': 8, '4': 1, '5': 3, '10': 'scheduleDate'},
  ],
};

/// Descriptor for `EngineForwardMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineForwardMessageRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVGb3J3YXJkTWVzc2FnZVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lkEhwK'
    'CnRvX2NoYXRfaWQYBCABKAlSCHRvQ2hhdElkEh8KC2Ryb3BfYXV0aG9yGAUgASgIUgpkcm9wQX'
    'V0aG9yEiMKDWRyb3BfY2FwdGlvbnMYBiABKAhSDGRyb3BDYXB0aW9ucxIWCgZzaWxlbnQYByAB'
    'KAhSBnNpbGVudBIjCg1zY2hlZHVsZV9kYXRlGAggASgDUgxzY2hlZHVsZURhdGU=');

@$core.Deprecated('Use engineResendAsOwnRequestDescriptor instead')
const EngineResendAsOwnRequest$json = {
  '1': 'EngineResendAsOwnRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'source_chat_id', '3': 2, '4': 1, '5': 9, '10': 'sourceChatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'to_chat_id', '3': 4, '4': 1, '5': 9, '10': 'toChatId'},
    {'1': 'silent', '3': 5, '4': 1, '5': 8, '10': 'silent'},
    {'1': 'schedule_date', '3': 6, '4': 1, '5': 3, '10': 'scheduleDate'},
  ],
};

/// Descriptor for `EngineResendAsOwnRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineResendAsOwnRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVSZXNlbmRBc093blJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEiQKDnNvdXJjZV9jaGF0X2lkGAIgASgJUgxzb3VyY2VDaGF0SWQSFQoGbXNnX2lkGAMgASgJ'
    'UgVtc2dJZBIcCgp0b19jaGF0X2lkGAQgASgJUgh0b0NoYXRJZBIWCgZzaWxlbnQYBSABKAhSBn'
    'NpbGVudBIjCg1zY2hlZHVsZV9kYXRlGAYgASgDUgxzY2hlZHVsZURhdGU=');

@$core.Deprecated('Use engineResendAlbumAsOwnRequestDescriptor instead')
const EngineResendAlbumAsOwnRequest$json = {
  '1': 'EngineResendAlbumAsOwnRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'source_chat_id', '3': 2, '4': 1, '5': 9, '10': 'sourceChatId'},
    {'1': 'msg_ids', '3': 3, '4': 3, '5': 9, '10': 'msgIds'},
    {'1': 'to_chat_id', '3': 4, '4': 1, '5': 9, '10': 'toChatId'},
    {'1': 'silent', '3': 5, '4': 1, '5': 8, '10': 'silent'},
    {'1': 'schedule_date', '3': 6, '4': 1, '5': 3, '10': 'scheduleDate'},
  ],
};

/// Descriptor for `EngineResendAlbumAsOwnRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineResendAlbumAsOwnRequestDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVSZXNlbmRBbGJ1bUFzT3duUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2'
    'NvdW50SWQSJAoOc291cmNlX2NoYXRfaWQYAiABKAlSDHNvdXJjZUNoYXRJZBIXCgdtc2dfaWRz'
    'GAMgAygJUgZtc2dJZHMSHAoKdG9fY2hhdF9pZBgEIAEoCVIIdG9DaGF0SWQSFgoGc2lsZW50GA'
    'UgASgIUgZzaWxlbnQSIwoNc2NoZWR1bGVfZGF0ZRgGIAEoA1IMc2NoZWR1bGVEYXRl');

@$core.Deprecated('Use engineSendContactRequestDescriptor instead')
const EngineSendContactRequest$json = {
  '1': 'EngineSendContactRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'to_chat_id', '3': 2, '4': 1, '5': 9, '10': 'toChatId'},
    {'1': 'phone', '3': 3, '4': 1, '5': 9, '10': 'phone'},
    {'1': 'first_name', '3': 4, '4': 1, '5': 9, '10': 'firstName'},
    {'1': 'last_name', '3': 5, '4': 1, '5': 9, '10': 'lastName'},
    {'1': 'user_id', '3': 6, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `EngineSendContactRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSendContactRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVTZW5kQ29udGFjdFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhwKCnRvX2NoYXRfaWQYAiABKAlSCHRvQ2hhdElkEhQKBXBob25lGAMgASgJUgVwaG9uZRId'
    'CgpmaXJzdF9uYW1lGAQgASgJUglmaXJzdE5hbWUSGwoJbGFzdF9uYW1lGAUgASgJUghsYXN0Tm'
    'FtZRIXCgd1c2VyX2lkGAYgASgJUgZ1c2VySWQ=');

@$core.Deprecated('Use engineSendContactResponseDescriptor instead')
const EngineSendContactResponse$json = {
  '1': 'EngineSendContactResponse',
  '2': [
    {'1': 'local_id', '3': 1, '4': 1, '5': 9, '10': 'localId'},
  ],
};

/// Descriptor for `EngineSendContactResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSendContactResponseDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVTZW5kQ29udGFjdFJlc3BvbnNlEhkKCGxvY2FsX2lkGAEgASgJUgdsb2NhbElk');

@$core.Deprecated('Use engineReactToMessageRequestDescriptor instead')
const EngineReactToMessageRequest$json = {
  '1': 'EngineReactToMessageRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'emoji', '3': 4, '4': 1, '5': 9, '10': 'emoji'},
  ],
};

/// Descriptor for `EngineReactToMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineReactToMessageRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVSZWFjdFRvTWVzc2FnZVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lkEhQK'
    'BWVtb2ppGAQgASgJUgVlbW9qaQ==');

@$core.Deprecated('Use enginePinMessageRequestDescriptor instead')
const EnginePinMessageRequest$json = {
  '1': 'EnginePinMessageRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'pinned', '3': 4, '4': 1, '5': 8, '10': 'pinned'},
  ],
};

/// Descriptor for `EnginePinMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List enginePinMessageRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVQaW5NZXNzYWdlUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'QSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhUKBm1zZ19pZBgDIAEoCVIFbXNnSWQSFgoGcGlu'
    'bmVkGAQgASgIUgZwaW5uZWQ=');

@$core.Deprecated('Use engineUploadFileRequestDescriptor instead')
const EngineUploadFileRequest$json = {
  '1': 'EngineUploadFileRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'file_path', '3': 3, '4': 1, '5': 9, '10': 'filePath'},
    {'1': 'caption', '3': 4, '4': 1, '5': 9, '10': 'caption'},
    {'1': 'silent', '3': 5, '4': 1, '5': 8, '10': 'silent'},
    {'1': 'schedule_date', '3': 6, '4': 1, '5': 5, '10': 'scheduleDate'},
    {'1': 'spoiler', '3': 7, '4': 1, '5': 8, '10': 'spoiler'},
    {'1': 'send_as_document', '3': 8, '4': 1, '5': 8, '10': 'sendAsDocument'},
    {'1': 'caption_above', '3': 9, '4': 1, '5': 8, '10': 'captionAbove'},
  ],
};

/// Descriptor for `EngineUploadFileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineUploadFileRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVVcGxvYWRGaWxlUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'QSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhsKCWZpbGVfcGF0aBgDIAEoCVIIZmlsZVBhdGgS'
    'GAoHY2FwdGlvbhgEIAEoCVIHY2FwdGlvbhIWCgZzaWxlbnQYBSABKAhSBnNpbGVudBIjCg1zY2'
    'hlZHVsZV9kYXRlGAYgASgFUgxzY2hlZHVsZURhdGUSGAoHc3BvaWxlchgHIAEoCFIHc3BvaWxl'
    'chIoChBzZW5kX2FzX2RvY3VtZW50GAggASgIUg5zZW5kQXNEb2N1bWVudBIjCg1jYXB0aW9uX2'
    'Fib3ZlGAkgASgIUgxjYXB0aW9uQWJvdmU=');

@$core.Deprecated('Use engineUploadFileResponseDescriptor instead')
const EngineUploadFileResponse$json = {
  '1': 'EngineUploadFileResponse',
  '2': [
    {'1': 'msg_id', '3': 1, '4': 1, '5': 9, '10': 'msgId'},
  ],
};

/// Descriptor for `EngineUploadFileResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineUploadFileResponseDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVVcGxvYWRGaWxlUmVzcG9uc2USFQoGbXNnX2lkGAEgASgJUgVtc2dJZA==');

@$core.Deprecated('Use engineRetryPendingRequestDescriptor instead')
const EngineRetryPendingRequest$json = {
  '1': 'EngineRetryPendingRequest',
  '2': [
    {'1': 'local_id', '3': 1, '4': 1, '5': 9, '10': 'localId'},
  ],
};

/// Descriptor for `EngineRetryPendingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineRetryPendingRequestDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVSZXRyeVBlbmRpbmdSZXF1ZXN0EhkKCGxvY2FsX2lkGAEgASgJUgdsb2NhbElk');

@$core.Deprecated('Use engineGetMessageRawRequestDescriptor instead')
const EngineGetMessageRawRequest$json = {
  '1': 'EngineGetMessageRawRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
  ],
};

/// Descriptor for `EngineGetMessageRawRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetMessageRawRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVHZXRNZXNzYWdlUmF3UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhUKBm1zZ19pZBgDIAEoCVIFbXNnSWQ=');

@$core.Deprecated('Use engineGetMessageRawResponseDescriptor instead')
const EngineGetMessageRawResponse$json = {
  '1': 'EngineGetMessageRawResponse',
  '2': [
    {'1': 'content_raw', '3': 1, '4': 1, '5': 12, '10': 'contentRaw'},
  ],
};

/// Descriptor for `EngineGetMessageRawResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetMessageRawResponseDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVHZXRNZXNzYWdlUmF3UmVzcG9uc2USHwoLY29udGVudF9yYXcYASABKAxSCmNvbn'
    'RlbnRSYXc=');

@$core.Deprecated('Use engineMemberInfoDescriptor instead')
const EngineMemberInfo$json = {
  '1': 'EngineMemberInfo',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
    {'1': 'display_name', '3': 3, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'avatar_b64', '3': 4, '4': 1, '5': 9, '10': 'avatarB64'},
    {'1': 'is_bot', '3': 5, '4': 1, '5': 8, '10': 'isBot'},
    {'1': 'is_online', '3': 6, '4': 1, '5': 8, '10': 'isOnline'},
    {'1': 'role', '3': 7, '4': 1, '5': 9, '10': 'role'},
  ],
};

/// Descriptor for `EngineMemberInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineMemberInfoDescriptor = $convert.base64Decode(
    'ChBFbmdpbmVNZW1iZXJJbmZvEhcKB3VzZXJfaWQYASABKAlSBnVzZXJJZBIaCgh1c2VybmFtZR'
    'gCIAEoCVIIdXNlcm5hbWUSIQoMZGlzcGxheV9uYW1lGAMgASgJUgtkaXNwbGF5TmFtZRIdCgph'
    'dmF0YXJfYjY0GAQgASgJUglhdmF0YXJCNjQSFQoGaXNfYm90GAUgASgIUgVpc0JvdBIbCglpc1'
    '9vbmxpbmUYBiABKAhSCGlzT25saW5lEhIKBHJvbGUYByABKAlSBHJvbGU=');

@$core.Deprecated('Use engineGetChatMembersRequestDescriptor instead')
const EngineGetChatMembersRequest$json = {
  '1': 'EngineGetChatMembersRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'limit', '3': 3, '4': 1, '5': 5, '10': 'limit'},
    {'1': 'offset', '3': 4, '4': 1, '5': 5, '10': 'offset'},
  ],
};

/// Descriptor for `EngineGetChatMembersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetChatMembersRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVHZXRDaGF0TWVtYmVyc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIUCgVsaW1pdBgDIAEoBVIFbGltaXQSFgoG'
    'b2Zmc2V0GAQgASgFUgZvZmZzZXQ=');

@$core.Deprecated('Use engineGetChatMembersResponseDescriptor instead')
const EngineGetChatMembersResponse$json = {
  '1': 'EngineGetChatMembersResponse',
  '2': [
    {'1': 'members', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineMemberInfo', '10': 'members'},
  ],
};

/// Descriptor for `EngineGetChatMembersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetChatMembersResponseDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVHZXRDaGF0TWVtYmVyc1Jlc3BvbnNlEjUKB21lbWJlcnMYASADKAsyGy51bmljbG'
    'llbnQuRW5naW5lTWVtYmVySW5mb1IHbWVtYmVycw==');

@$core.Deprecated('Use engineSetActiveChatRequestDescriptor instead')
const EngineSetActiveChatRequest$json = {
  '1': 'EngineSetActiveChatRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineSetActiveChatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSetActiveChatRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVTZXRBY3RpdmVDaGF0UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElk');

@$core.Deprecated('Use engineSearchResultDescriptor instead')
const EngineSearchResult$json = {
  '1': 'EngineSearchResult',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'sender_name', '3': 4, '4': 1, '5': 9, '10': 'senderName'},
    {'1': 'text', '3': 5, '4': 1, '5': 9, '10': 'text'},
    {'1': 'timestamp', '3': 6, '4': 1, '5': 3, '10': 'timestamp'},
    {'1': 'chat_title', '3': 7, '4': 1, '5': 9, '10': 'chatTitle'},
  ],
};

/// Descriptor for `EngineSearchResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSearchResultDescriptor = $convert.base64Decode(
    'ChJFbmdpbmVTZWFyY2hSZXN1bHQSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudElkEhcKB2'
    'NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lkEh8KC3NlbmRlcl9u'
    'YW1lGAQgASgJUgpzZW5kZXJOYW1lEhIKBHRleHQYBSABKAlSBHRleHQSHAoJdGltZXN0YW1wGA'
    'YgASgDUgl0aW1lc3RhbXASHQoKY2hhdF90aXRsZRgHIAEoCVIJY2hhdFRpdGxl');

@$core.Deprecated('Use engineSearchMessagesRequestDescriptor instead')
const EngineSearchMessagesRequest$json = {
  '1': 'EngineSearchMessagesRequest',
  '2': [
    {'1': 'query', '3': 1, '4': 1, '5': 9, '10': 'query'},
    {'1': 'account_id', '3': 2, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'limit', '3': 3, '4': 1, '5': 5, '10': 'limit'},
    {'1': 'chat_id', '3': 4, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineSearchMessagesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSearchMessagesRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVTZWFyY2hNZXNzYWdlc1JlcXVlc3QSFAoFcXVlcnkYASABKAlSBXF1ZXJ5Eh0KCm'
    'FjY291bnRfaWQYAiABKAlSCWFjY291bnRJZBIUCgVsaW1pdBgDIAEoBVIFbGltaXQSFwoHY2hhdF'
    '9pZBgEIAEoCVIGY2hhdElk');

@$core.Deprecated('Use engineSearchMessagesResponseDescriptor instead')
const EngineSearchMessagesResponse$json = {
  '1': 'EngineSearchMessagesResponse',
  '2': [
    {'1': 'results', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineSearchResult', '10': 'results'},
  ],
};

/// Descriptor for `EngineSearchMessagesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSearchMessagesResponseDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVTZWFyY2hNZXNzYWdlc1Jlc3BvbnNlEjcKB3Jlc3VsdHMYASADKAsyHS51bmljbG'
    'llbnQuRW5naW5lU2VhcmNoUmVzdWx0UgdyZXN1bHRz');

@$core.Deprecated('Use engineSearchChatsRequestDescriptor instead')
const EngineSearchChatsRequest$json = {
  '1': 'EngineSearchChatsRequest',
  '2': [
    {'1': 'query', '3': 1, '4': 1, '5': 9, '10': 'query'},
    {'1': 'limit', '3': 2, '4': 1, '5': 5, '10': 'limit'},
  ],
};

/// Descriptor for `EngineSearchChatsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSearchChatsRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVTZWFyY2hDaGF0c1JlcXVlc3QSFAoFcXVlcnkYASABKAlSBXF1ZXJ5EhQKBWxpbW'
    'l0GAIgASgFUgVsaW1pdA==');

@$core.Deprecated('Use engineSearchChatsResponseDescriptor instead')
const EngineSearchChatsResponse$json = {
  '1': 'EngineSearchChatsResponse',
  '2': [
    {'1': 'chats', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineChatInfo', '10': 'chats'},
  ],
};

/// Descriptor for `EngineSearchChatsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSearchChatsResponseDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVTZWFyY2hDaGF0c1Jlc3BvbnNlEi8KBWNoYXRzGAEgAygLMhkudW5pY2xpZW50Lk'
    'VuZ2luZUNoYXRJbmZvUgVjaGF0cw==');

@$core.Deprecated('Use engineRequestDownloadRequestDescriptor instead')
const EngineRequestDownloadRequest$json = {
  '1': 'EngineRequestDownloadRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'seq', '3': 4, '4': 1, '5': 5, '10': 'seq'},
    {'1': 'priority', '3': 5, '4': 1, '5': 5, '10': 'priority'},
  ],
};

/// Descriptor for `EngineRequestDownloadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineRequestDownloadRequestDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVSZXF1ZXN0RG93bmxvYWRSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY2'
    '91bnRJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSFQoGbXNnX2lkGAMgASgJUgVtc2dJZBIQ'
    'CgNzZXEYBCABKAVSA3NlcRIaCghwcmlvcml0eRgFIAEoBVIIcHJpb3JpdHk=');

@$core.Deprecated('Use engineCancelDownloadRequestDescriptor instead')
const EngineCancelDownloadRequest$json = {
  '1': 'EngineCancelDownloadRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'seq', '3': 4, '4': 1, '5': 5, '10': 'seq'},
  ],
};

/// Descriptor for `EngineCancelDownloadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCancelDownloadRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVDYW5jZWxEb3dubG9hZFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lkEhAK'
    'A3NlcRgEIAEoBVIDc2Vx');

@$core.Deprecated('Use engineGetCacheSizeResponseDescriptor instead')
const EngineGetCacheSizeResponse$json = {
  '1': 'EngineGetCacheSizeResponse',
  '2': [
    {'1': 'size_bytes', '3': 1, '4': 1, '5': 3, '10': 'sizeBytes'},
  ],
};

/// Descriptor for `EngineGetCacheSizeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetCacheSizeResponseDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVHZXRDYWNoZVNpemVSZXNwb25zZRIdCgpzaXplX2J5dGVzGAEgASgDUglzaXplQn'
    'l0ZXM=');

@$core.Deprecated('Use engineClearCacheRequestDescriptor instead')
const EngineClearCacheRequest$json = {
  '1': 'EngineClearCacheRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineClearCacheRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineClearCacheRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVDbGVhckNhY2hlUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'Q=');

@$core.Deprecated('Use engineGetSharedMediaRequestDescriptor instead')
const EngineGetSharedMediaRequest$json = {
  '1': 'EngineGetSharedMediaRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'media_type', '3': 3, '4': 1, '5': 9, '10': 'mediaType'},
    {'1': 'limit', '3': 4, '4': 1, '5': 5, '10': 'limit'},
    {'1': 'offset', '3': 5, '4': 1, '5': 5, '10': 'offset'},
    {'1': 'query', '3': 6, '4': 1, '5': 9, '10': 'query'},
  ],
};

/// Descriptor for `EngineGetSharedMediaRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSharedMediaRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVHZXRTaGFyZWRNZWRpYVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIdCgptZWRpYV90eXBlGAMgASgJUgltZWRp'
    'YVR5cGUSFAoFbGltaXQYBCABKAVSBWxpbWl0EhYKBm9mZnNldBgFIAEoBVIGb2Zmc2V0');

@$core.Deprecated('Use engineSharedMediaItemDescriptor instead')
const EngineSharedMediaItem$json = {
  '1': 'EngineSharedMediaItem',
  '2': [
    {'1': 'msg_id', '3': 1, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'timestamp', '3': 2, '4': 1, '5': 3, '10': 'timestamp'},
    {'1': 'media_type', '3': 3, '4': 1, '5': 5, '10': 'mediaType'},
    {'1': 'file_name', '3': 4, '4': 1, '5': 9, '10': 'fileName'},
    {'1': 'mime_type', '3': 5, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'file_size', '3': 6, '4': 1, '5': 3, '10': 'fileSize'},
    {'1': 'thumb_b64', '3': 7, '4': 1, '5': 9, '10': 'thumbB64'},
    {'1': 'local_path', '3': 8, '4': 1, '5': 9, '10': 'localPath'},
    {'1': 'width', '3': 9, '4': 1, '5': 5, '10': 'width'},
    {'1': 'height', '3': 10, '4': 1, '5': 5, '10': 'height'},
    {'1': 'duration', '3': 11, '4': 1, '5': 5, '10': 'duration'},
    {'1': 'waveform', '3': 12, '4': 1, '5': 12, '10': 'waveform'},
  ],
};

/// Descriptor for `EngineSharedMediaItem`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSharedMediaItemDescriptor = $convert.base64Decode(
    'ChVFbmdpbmVTaGFyZWRNZWRpYUl0ZW0SFQoGbXNnX2lkGAEgASgJUgVtc2dJZBIcCgl0aW1lc3'
    'RhbXAYAiABKANSCXRpbWVzdGFtcBIdCgptZWRpYV90eXBlGAMgASgFUgltZWRpYVR5cGUSGwoJ'
    'ZmlsZV9uYW1lGAQgASgJUghmaWxlTmFtZRIbCgltaW1lX3R5cGUYBSABKAlSCG1pbWVUeXBlEh'
    'sKCWZpbGVfc2l6ZRgGIAEoA1IIZmlsZVNpemUSGwoJdGh1bWJfYjY0GAcgASgJUgh0aHVtYkI2'
    'NBIdCgpsb2NhbF9wYXRoGAggASgJUglsb2NhbFBhdGgSFAoFd2lkdGgYCSABKAVSBXdpZHRoEh'
    'YKBmhlaWdodBgKIAEoBVIGaGVpZ2h0EhoKCGR1cmF0aW9uGAsgASgFUghkdXJhdGlvbhIaCgh3'
    'YXZlZm9ybRgMIAEoDFIId2F2ZWZvcm0=');

@$core.Deprecated('Use engineGetSharedMediaResponseDescriptor instead')
const EngineGetSharedMediaResponse$json = {
  '1': 'EngineGetSharedMediaResponse',
  '2': [
    {'1': 'items', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineSharedMediaItem', '10': 'items'},
  ],
};

/// Descriptor for `EngineGetSharedMediaResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSharedMediaResponseDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVHZXRTaGFyZWRNZWRpYVJlc3BvbnNlEjYKBWl0ZW1zGAEgAygLMiAudW5pY2xpZW'
    '50LkVuZ2luZVNoYXJlZE1lZGlhSXRlbVIFaXRlbXM=');

@$core.Deprecated('Use engineGetSharedMediaCountsRequestDescriptor instead')
const EngineGetSharedMediaCountsRequest$json = {
  '1': 'EngineGetSharedMediaCountsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineGetSharedMediaCountsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSharedMediaCountsRequestDescriptor = $convert.base64Decode(
    'CiFFbmdpbmVHZXRTaGFyZWRNZWRpYUNvdW50c1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCV'
    'IJYWNjb3VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZA==');

@$core.Deprecated('Use engineSharedMediaCountDescriptor instead')
const EngineSharedMediaCount$json = {
  '1': 'EngineSharedMediaCount',
  '2': [
    {'1': 'media_type', '3': 1, '4': 1, '5': 9, '10': 'mediaType'},
    {'1': 'count', '3': 2, '4': 1, '5': 5, '10': 'count'},
  ],
};

/// Descriptor for `EngineSharedMediaCount`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSharedMediaCountDescriptor = $convert.base64Decode(
    'ChZFbmdpbmVTaGFyZWRNZWRpYUNvdW50Eh0KCm1lZGlhX3R5cGUYASABKAlSCW1lZGlhVHlwZR'
    'IUCgVjb3VudBgCIAEoBVIFY291bnQ=');

@$core.Deprecated('Use engineGetSharedMediaCountsResponseDescriptor instead')
const EngineGetSharedMediaCountsResponse$json = {
  '1': 'EngineGetSharedMediaCountsResponse',
  '2': [
    {'1': 'counts', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineSharedMediaCount', '10': 'counts'},
  ],
};

/// Descriptor for `EngineGetSharedMediaCountsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSharedMediaCountsResponseDescriptor = $convert.base64Decode(
    'CiJFbmdpbmVHZXRTaGFyZWRNZWRpYUNvdW50c1Jlc3BvbnNlEjkKBmNvdW50cxgBIAMoCzIhLn'
    'VuaWNsaWVudC5FbmdpbmVTaGFyZWRNZWRpYUNvdW50UgZjb3VudHM=');

@$core.Deprecated('Use engineGetConfigResponseDescriptor instead')
const EngineGetConfigResponse$json = {
  '1': 'EngineGetConfigResponse',
  '2': [
    {'1': 'theme', '3': 1, '4': 1, '5': 9, '10': 'theme'},
    {'1': 'accent_color', '3': 2, '4': 1, '5': 9, '10': 'accentColor'},
    {'1': 'font_scale', '3': 3, '4': 1, '5': 1, '10': 'fontScale'},
    {'1': 'language', '3': 4, '4': 1, '5': 9, '10': 'language'},
    {'1': 'download_dir', '3': 5, '4': 1, '5': 9, '10': 'downloadDir'},
    {'1': 'max_cache_size', '3': 6, '4': 1, '5': 3, '10': 'maxCacheSize'},
    {'1': 'send_read_receipts', '3': 7, '4': 1, '5': 8, '10': 'sendReadReceipts'},
    {'1': 'send_typing', '3': 8, '4': 1, '5': 8, '10': 'sendTyping'},
    {'1': 'notify_dms', '3': 9, '4': 1, '5': 8, '10': 'notifyDms'},
    {'1': 'notify_groups', '3': 10, '4': 1, '5': 8, '10': 'notifyGroups'},
    {'1': 'notify_mentions_only', '3': 11, '4': 1, '5': 8, '10': 'notifyMentionsOnly'},
    {'1': 'send_read_stories', '3': 12, '4': 1, '5': 8, '10': 'sendReadStories'},
    {'1': 'send_online_packets', '3': 13, '4': 1, '5': 8, '10': 'sendOnlinePackets'},
    {'1': 'send_offline_after_online', '3': 14, '4': 1, '5': 8, '10': 'sendOfflineAfterOnline'},
    {'1': 'mark_read_after_action', '3': 15, '4': 1, '5': 8, '10': 'markReadAfterAction'},
    {'1': 'use_scheduled_messages', '3': 16, '4': 1, '5': 8, '10': 'useScheduledMessages'},
    {'1': 'send_without_sound', '3': 17, '4': 1, '5': 8, '10': 'sendWithoutSound'},
  ],
};

/// Descriptor for `EngineGetConfigResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetConfigResponseDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVHZXRDb25maWdSZXNwb25zZRIUCgV0aGVtZRgBIAEoCVIFdGhlbWUSIQoMYWNjZW'
    '50X2NvbG9yGAIgASgJUgthY2NlbnRDb2xvchIdCgpmb250X3NjYWxlGAMgASgBUglmb250U2Nh'
    'bGUSGgoIbGFuZ3VhZ2UYBCABKAlSCGxhbmd1YWdlEiEKDGRvd25sb2FkX2RpchgFIAEoCVILZG'
    '93bmxvYWREaXISJAoObWF4X2NhY2hlX3NpemUYBiABKANSDG1heENhY2hlU2l6ZRIsChJzZW5k'
    'X3JlYWRfcmVjZWlwdHMYByABKAhSEHNlbmRSZWFkUmVjZWlwdHMSHwoLc2VuZF90eXBpbmcYCC'
    'ABKAhSCnNlbmRUeXBpbmcSHQoKbm90aWZ5X2RtcxgJIAEoCFIJbm90aWZ5RG1zEiMKDW5vdGlm'
    'eV9ncm91cHMYCiABKAhSDG5vdGlmeUdyb3VwcxIwChRub3RpZnlfbWVudGlvbnNfb25seRgLIA'
    'EoCFISbm90aWZ5TWVudGlvbnNPbmx5EioKEXNlbmRfcmVhZF9zdG9yaWVzGAwgASgIUg9zZW5k'
    'UmVhZFN0b3JpZXMSLgoTc2VuZF9vbmxpbmVfcGFja2V0cxgNIAEoCFIRc2VuZE9ubGluZVBhY2'
    'tldHMSOQoZc2VuZF9vZmZsaW5lX2FmdGVyX29ubGluZRgOIAEoCFIWc2VuZE9mZmxpbmVBZnRl'
    'ck9ubGluZRIzChZtYXJrX3JlYWRfYWZ0ZXJfYWN0aW9uGA8gASgIUhNtYXJrUmVhZEFmdGVyQW'
    'N0aW9uEjQKFnVzZV9zY2hlZHVsZWRfbWVzc2FnZXMYECABKAhSFHVzZVNjaGVkdWxlZE1lc3Nh'
    'Z2VzEiwKEnNlbmRfd2l0aG91dF9zb3VuZBgRIAEoCFIQc2VuZFdpdGhvdXRTb3VuZA==');

@$core.Deprecated('Use engineUpdateConfigRequestDescriptor instead')
const EngineUpdateConfigRequest$json = {
  '1': 'EngineUpdateConfigRequest',
  '2': [
    {'1': 'theme', '3': 1, '4': 1, '5': 9, '10': 'theme'},
    {'1': 'accent_color', '3': 2, '4': 1, '5': 9, '10': 'accentColor'},
    {'1': 'font_scale', '3': 3, '4': 1, '5': 1, '10': 'fontScale'},
    {'1': 'language', '3': 4, '4': 1, '5': 9, '10': 'language'},
    {'1': 'max_cache_size', '3': 5, '4': 1, '5': 3, '10': 'maxCacheSize'},
    {'1': 'send_read_receipts', '3': 6, '4': 1, '5': 8, '10': 'sendReadReceipts'},
    {'1': 'has_send_read_receipts', '3': 7, '4': 1, '5': 8, '10': 'hasSendReadReceipts'},
    {'1': 'send_typing', '3': 8, '4': 1, '5': 8, '10': 'sendTyping'},
    {'1': 'has_send_typing', '3': 9, '4': 1, '5': 8, '10': 'hasSendTyping'},
    {'1': 'notify_dms', '3': 10, '4': 1, '5': 8, '10': 'notifyDms'},
    {'1': 'has_notify_dms', '3': 11, '4': 1, '5': 8, '10': 'hasNotifyDms'},
    {'1': 'notify_groups', '3': 12, '4': 1, '5': 8, '10': 'notifyGroups'},
    {'1': 'has_notify_groups', '3': 13, '4': 1, '5': 8, '10': 'hasNotifyGroups'},
    {'1': 'notify_mentions_only', '3': 14, '4': 1, '5': 8, '10': 'notifyMentionsOnly'},
    {'1': 'has_notify_mentions_only', '3': 15, '4': 1, '5': 8, '10': 'hasNotifyMentionsOnly'},
    {'1': 'send_read_stories', '3': 16, '4': 1, '5': 8, '10': 'sendReadStories'},
    {'1': 'has_send_read_stories', '3': 17, '4': 1, '5': 8, '10': 'hasSendReadStories'},
    {'1': 'send_online_packets', '3': 18, '4': 1, '5': 8, '10': 'sendOnlinePackets'},
    {'1': 'has_send_online_packets', '3': 19, '4': 1, '5': 8, '10': 'hasSendOnlinePackets'},
    {'1': 'send_offline_after_online', '3': 20, '4': 1, '5': 8, '10': 'sendOfflineAfterOnline'},
    {'1': 'has_send_offline_after_online', '3': 21, '4': 1, '5': 8, '10': 'hasSendOfflineAfterOnline'},
    {'1': 'mark_read_after_action', '3': 22, '4': 1, '5': 8, '10': 'markReadAfterAction'},
    {'1': 'has_mark_read_after_action', '3': 23, '4': 1, '5': 8, '10': 'hasMarkReadAfterAction'},
    {'1': 'use_scheduled_messages', '3': 24, '4': 1, '5': 8, '10': 'useScheduledMessages'},
    {'1': 'has_use_scheduled_messages', '3': 25, '4': 1, '5': 8, '10': 'hasUseScheduledMessages'},
    {'1': 'send_without_sound', '3': 26, '4': 1, '5': 8, '10': 'sendWithoutSound'},
    {'1': 'has_send_without_sound', '3': 27, '4': 1, '5': 8, '10': 'hasSendWithoutSound'},
    {'1': 'send_upload_progress', '3': 28, '4': 1, '5': 8, '10': 'sendUploadProgress'},
    {'1': 'has_send_upload_progress', '3': 29, '4': 1, '5': 8, '10': 'hasSendUploadProgress'},
  ],
};

/// Descriptor for `EngineUpdateConfigRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineUpdateConfigRequestDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVVcGRhdGVDb25maWdSZXF1ZXN0EhQKBXRoZW1lGAEgASgJUgV0aGVtZRIhCgxhY2'
    'NlbnRfY29sb3IYAiABKAlSC2FjY2VudENvbG9yEh0KCmZvbnRfc2NhbGUYAyABKAFSCWZvbnRT'
    'Y2FsZRIaCghsYW5ndWFnZRgEIAEoCVIIbGFuZ3VhZ2USJAoObWF4X2NhY2hlX3NpemUYBSABKA'
    'NSDG1heENhY2hlU2l6ZRIsChJzZW5kX3JlYWRfcmVjZWlwdHMYBiABKAhSEHNlbmRSZWFkUmVj'
    'ZWlwdHMSMwoWaGFzX3NlbmRfcmVhZF9yZWNlaXB0cxgHIAEoCFITaGFzU2VuZFJlYWRSZWNlaX'
    'B0cxIfCgtzZW5kX3R5cGluZxgIIAEoCFIKc2VuZFR5cGluZxImCg9oYXNfc2VuZF90eXBpbmcY'
    'CSABKAhSDWhhc1NlbmRUeXBpbmcSHQoKbm90aWZ5X2RtcxgKIAEoCFIJbm90aWZ5RG1zEiQKDm'
    'hhc19ub3RpZnlfZG1zGAsgASgIUgxoYXNOb3RpZnlEbXMSIwoNbm90aWZ5X2dyb3VwcxgMIAEo'
    'CFIMbm90aWZ5R3JvdXBzEioKEWhhc19ub3RpZnlfZ3JvdXBzGA0gASgIUg9oYXNOb3RpZnlHcm'
    '91cHMSMAoUbm90aWZ5X21lbnRpb25zX29ubHkYDiABKAhSEm5vdGlmeU1lbnRpb25zT25seRI3'
    'ChhoYXNfbm90aWZ5X21lbnRpb25zX29ubHkYDyABKAhSFWhhc05vdGlmeU1lbnRpb25zT25seR'
    'IqChFzZW5kX3JlYWRfc3RvcmllcxgQIAEoCFIPc2VuZFJlYWRTdG9yaWVzEjEKFWhhc19zZW5k'
    'X3JlYWRfc3RvcmllcxgRIAEoCFISaGFzU2VuZFJlYWRTdG9yaWVzEi4KE3NlbmRfb25saW5lX3'
    'BhY2tldHMYEiABKAhSEXNlbmRPbmxpbmVQYWNrZXRzEjUKF2hhc19zZW5kX29ubGluZV9wYWNr'
    'ZXRzGBMgASgIUhRoYXNTZW5kT25saW5lUGFja2V0cxI5ChlzZW5kX29mZmxpbmVfYWZ0ZXJfb2'
    '5saW5lGBQgASgIUhZzZW5kT2ZmbGluZUFmdGVyT25saW5lEkAKHWhhc19zZW5kX29mZmxpbmVf'
    'YWZ0ZXJfb25saW5lGBUgASgIUhloYXNTZW5kT2ZmbGluZUFmdGVyT25saW5lEjMKFm1hcmtfcm'
    'VhZF9hZnRlcl9hY3Rpb24YFiABKAhSE21hcmtSZWFkQWZ0ZXJBY3Rpb24SOgoaaGFzX21hcmtf'
    'cmVhZF9hZnRlcl9hY3Rpb24YFyABKAhSFmhhc01hcmtSZWFkQWZ0ZXJBY3Rpb24SNAoWdXNlX3'
    'NjaGVkdWxlZF9tZXNzYWdlcxgYIAEoCFIUdXNlU2NoZWR1bGVkTWVzc2FnZXMSOwoaaGFzX3Vz'
    'ZV9zY2hlZHVsZWRfbWVzc2FnZXMYGSABKAhSF2hhc1VzZVNjaGVkdWxlZE1lc3NhZ2VzEiwKEn'
    'NlbmRfd2l0aG91dF9zb3VuZBgaIAEoCFIQc2VuZFdpdGhvdXRTb3VuZBIzChZoYXNfc2VuZF93'
    'aXRob3V0X3NvdW5kGBsgASgIUhNoYXNTZW5kV2l0aG91dFNvdW5kEjAKFHNlbmRfdXBsb2FkX3'
    'Byb2dyZXNzGBwgASgIUhJzZW5kVXBsb2FkUHJvZ3Jlc3MSNwoYaGFzX3NlbmRfdXBsb2FkX3By'
    'b2dyZXNzGB0gASgIUhVoYXNTZW5kVXBsb2FkUHJvZ3Jlc3M=');

@$core.Deprecated('Use engineFolderInfoDescriptor instead')
const EngineFolderInfo$json = {
  '1': 'EngineFolderInfo',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'chat_ids', '3': 3, '4': 3, '5': 9, '10': 'chatIds'},
    {'1': 'exclude_chat_ids', '3': 4, '4': 3, '5': 9, '10': 'excludeChatIds'},
    {'1': 'pinned_chat_ids', '3': 5, '4': 3, '5': 9, '10': 'pinnedChatIds'},
    {'1': 'contacts', '3': 6, '4': 1, '5': 8, '10': 'contacts'},
    {'1': 'non_contacts', '3': 7, '4': 1, '5': 8, '10': 'nonContacts'},
    {'1': 'groups', '3': 8, '4': 1, '5': 8, '10': 'groups'},
    {'1': 'channels', '3': 9, '4': 1, '5': 8, '10': 'channels'},
    {'1': 'bots', '3': 10, '4': 1, '5': 8, '10': 'bots'},
    {'1': 'exclude_muted', '3': 11, '4': 1, '5': 8, '10': 'excludeMuted'},
    {'1': 'exclude_read', '3': 12, '4': 1, '5': 8, '10': 'excludeRead'},
    {'1': 'exclude_archived', '3': 13, '4': 1, '5': 8, '10': 'excludeArchived'},
    {'1': 'is_chat_list', '3': 14, '4': 1, '5': 8, '10': 'isChatList'},
    {'1': 'emoticon', '3': 15, '4': 1, '5': 9, '10': 'emoticon'},
  ],
};

/// Descriptor for `EngineFolderInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineFolderInfoDescriptor = $convert.base64Decode(
    'ChBFbmdpbmVGb2xkZXJJbmZvEg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEh'
    'kKCGNoYXRfaWRzGAMgAygJUgdjaGF0SWRzEigKEGV4Y2x1ZGVfY2hhdF9pZHMYBCADKAlSDmV4'
    'Y2x1ZGVDaGF0SWRzEiYKD3Bpbm5lZF9jaGF0X2lkcxgFIAMoCVINcGlubmVkQ2hhdElkcxIaCg'
    'hjb250YWN0cxgGIAEoCFIIY29udGFjdHMSIQoMbm9uX2NvbnRhY3RzGAcgASgIUgtub25Db250'
    'YWN0cxIWCgZncm91cHMYCCABKAhSBmdyb3VwcxIaCghjaGFubmVscxgJIAEoCFIIY2hhbm5lbH'
    'MSEgoEYm90cxgKIAEoCFIEYm90cxIjCg1leGNsdWRlX211dGVkGAsgASgIUgxleGNsdWRlTXV0'
    'ZWQSIQoMZXhjbHVkZV9yZWFkGAwgASgIUgtleGNsdWRlUmVhZBIpChBleGNsdWRlX2FyY2hpdm'
    'VkGA0gASgIUg9leGNsdWRlQXJjaGl2ZWQSIAoMaXNfY2hhdF9saXN0GA4gASgIUgppc0NoYXRM'
    'aXN0EhoKCGVtb3RpY29uGA8gASgJUghlbW90aWNvbg==');

@$core.Deprecated('Use engineGetFoldersRequestDescriptor instead')
const EngineGetFoldersRequest$json = {
  '1': 'EngineGetFoldersRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetFoldersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetFoldersRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVHZXRGb2xkZXJzUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'Q=');

@$core.Deprecated('Use engineGetFoldersResponseDescriptor instead')
const EngineGetFoldersResponse$json = {
  '1': 'EngineGetFoldersResponse',
  '2': [
    {'1': 'folders', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineFolderInfo', '10': 'folders'},
  ],
};

/// Descriptor for `EngineGetFoldersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetFoldersResponseDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVHZXRGb2xkZXJzUmVzcG9uc2USNQoHZm9sZGVycxgBIAMoCzIbLnVuaWNsaWVudC'
    '5FbmdpbmVGb2xkZXJJbmZvUgdmb2xkZXJz');

@$core.Deprecated('Use engineDeleteFolderRequestDescriptor instead')
const EngineDeleteFolderRequest$json = {
  '1': 'EngineDeleteFolderRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'folder_id', '3': 2, '4': 1, '5': 9, '10': 'folderId'},
  ],
};

/// Descriptor for `EngineDeleteFolderRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineDeleteFolderRequestDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVEZWxldGVGb2xkZXJSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bn'
    'RJZBIbCglmb2xkZXJfaWQYAiABKAlSCGZvbGRlcklk');

@$core.Deprecated('Use engineEditFolderRequestDescriptor instead')
const EngineEditFolderRequest$json = {
  '1': 'EngineEditFolderRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'folder_id', '3': 2, '4': 1, '5': 9, '10': 'folderId'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
  ],
};

/// Descriptor for `EngineEditFolderRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineEditFolderRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVFZGl0Rm9sZGVyUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'QSGwoJZm9sZGVyX2lkGAIgASgJUghmb2xkZXJJZBIUCgV0aXRsZRgDIAEoCVIFdGl0bGU=');

@$core.Deprecated('Use engineGetPinnedMessagesRequestDescriptor instead')
const EngineGetPinnedMessagesRequest$json = {
  '1': 'EngineGetPinnedMessagesRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineGetPinnedMessagesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetPinnedMessagesRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVHZXRQaW5uZWRNZXNzYWdlc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZA==');

@$core.Deprecated('Use engineGetPinnedMessagesResponseDescriptor instead')
const EngineGetPinnedMessagesResponse$json = {
  '1': 'EngineGetPinnedMessagesResponse',
  '2': [
    {'1': 'messages', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineCachedMessage', '10': 'messages'},
  ],
};

/// Descriptor for `EngineGetPinnedMessagesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetPinnedMessagesResponseDescriptor = $convert.base64Decode(
    'Ch9FbmdpbmVHZXRQaW5uZWRNZXNzYWdlc1Jlc3BvbnNlEjoKCG1lc3NhZ2VzGAEgAygLMh4udW'
    '5pY2xpZW50LkVuZ2luZUNhY2hlZE1lc3NhZ2VSCG1lc3NhZ2Vz');

@$core.Deprecated('Use engineCreateChannelRequestDescriptor instead')
const EngineCreateChannelRequest$json = {
  '1': 'EngineCreateChannelRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'description', '3': 3, '4': 1, '5': 9, '10': 'description'},
  ],
};

/// Descriptor for `EngineCreateChannelRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCreateChannelRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVDcmVhdGVDaGFubmVsUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSEgoEbmFtZRgCIAEoCVIEbmFtZRIgCgtkZXNjcmlwdGlvbhgDIAEoCVILZGVzY3JpcHRp'
    'b24=');

@$core.Deprecated('Use engineCreateChannelResponseDescriptor instead')
const EngineCreateChannelResponse$json = {
  '1': 'EngineCreateChannelResponse',
  '2': [
    {'1': 'chat', '3': 1, '4': 1, '5': 11, '6': '.uniclient.EngineChatInfo', '10': 'chat'},
  ],
};

/// Descriptor for `EngineCreateChannelResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCreateChannelResponseDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVDcmVhdGVDaGFubmVsUmVzcG9uc2USLQoEY2hhdBgBIAEoCzIZLnVuaWNsaWVudC'
    '5FbmdpbmVDaGF0SW5mb1IEY2hhdA==');

@$core.Deprecated('Use engineCreateGroupRequestDescriptor instead')
const EngineCreateGroupRequest$json = {
  '1': 'EngineCreateGroupRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'members', '3': 3, '4': 3, '5': 9, '10': 'members'},
  ],
};

/// Descriptor for `EngineCreateGroupRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCreateGroupRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVDcmVhdGVHcm91cFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhIKBG5hbWUYAiABKAlSBG5hbWUSGAoHbWVtYmVycxgDIAMoCVIHbWVtYmVycw==');

@$core.Deprecated('Use engineCreateGroupResponseDescriptor instead')
const EngineCreateGroupResponse$json = {
  '1': 'EngineCreateGroupResponse',
  '2': [
    {'1': 'chat', '3': 1, '4': 1, '5': 11, '6': '.uniclient.EngineChatInfo', '10': 'chat'},
  ],
};

/// Descriptor for `EngineCreateGroupResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCreateGroupResponseDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVDcmVhdGVHcm91cFJlc3BvbnNlEi0KBGNoYXQYASABKAsyGS51bmljbGllbnQuRW'
    '5naW5lQ2hhdEluZm9SBGNoYXQ=');

@$core.Deprecated('Use engineContactInfoDescriptor instead')
const EngineContactInfo$json = {
  '1': 'EngineContactInfo',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
    {'1': 'display_name', '3': 3, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'phone', '3': 4, '4': 1, '5': 9, '10': 'phone'},
    {'1': 'avatar_b64', '3': 5, '4': 1, '5': 9, '10': 'avatarB64'},
    {'1': 'is_bot', '3': 6, '4': 1, '5': 8, '10': 'isBot'},
    {'1': 'is_online', '3': 7, '4': 1, '5': 8, '10': 'isOnline'},
    {'1': 'story_count', '3': 8, '4': 1, '5': 5, '10': 'storyCount'},
    {'1': 'has_unread_story', '3': 9, '4': 1, '5': 8, '10': 'hasUnreadStory'},
    {'1': 'is_verified', '3': 10, '4': 1, '5': 8, '10': 'isVerified'},
    {'1': 'is_premium', '3': 11, '4': 1, '5': 8, '10': 'isPremium'},
    {'1': 'is_scam', '3': 12, '4': 1, '5': 8, '10': 'isScam'},
    {'1': 'is_fake', '3': 13, '4': 1, '5': 8, '10': 'isFake'},
    {'1': 'last_seen_kind', '3': 14, '4': 1, '5': 9, '10': 'lastSeenKind'},
    {'1': 'last_seen_ts', '3': 15, '4': 1, '5': 3, '10': 'lastSeenTs'},
    {'1': 'is_mutual_contact', '3': 16, '4': 1, '5': 8, '10': 'isMutualContact'},
    {'1': 'stars_per_message', '3': 17, '4': 1, '5': 3, '10': 'starsPerMessage'},
  ],
};

/// Descriptor for `EngineContactInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineContactInfoDescriptor = $convert.base64Decode(
    'ChFFbmdpbmVDb250YWN0SW5mbxIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQSGgoIdXNlcm5hbW'
    'UYAiABKAlSCHVzZXJuYW1lEiEKDGRpc3BsYXlfbmFtZRgDIAEoCVILZGlzcGxheU5hbWUSFAoF'
    'cGhvbmUYBCABKAlSBXBob25lEh0KCmF2YXRhcl9iNjQYBSABKAlSCWF2YXRhckI2NBIVCgZpc1'
    '9ib3QYBiABKAhSBWlzQm90EhsKCWlzX29ubGluZRgHIAEoCFIIaXNPbmxpbmUSHwoLc3Rvcnlf'
    'Y291bnQYCCABKAVSCnN0b3J5Q291bnQSKAoQaGFzX3VucmVhZF9zdG9yeRgJIAEoCFIOaGFzVW'
    '5yZWFkU3RvcnkSHwoLaXNfdmVyaWZpZWQYCiABKAhSCmlzVmVyaWZpZWQSHQoKaXNfcHJlbWl1'
    'bRgLIAEoCFIJaXNQcmVtaXVtEhcKB2lzX3NjYW0YDCABKAhSBmlzU2NhbRIXCgdpc19mYWtlGA'
    '0gASgIUgZpc0Zha2USJAoObGFzdF9zZWVuX2tpbmQYDiABKAlSDGxhc3RTZWVuS2luZBIgCgxs'
    'YXN0X3NlZW5fdHMYDyABKANSCmxhc3RTZWVuVHM=');

@$core.Deprecated('Use engineGetContactsRequestDescriptor instead')
const EngineGetContactsRequest$json = {
  '1': 'EngineGetContactsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetContactsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetContactsRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVHZXRDb250YWN0c1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lk');

@$core.Deprecated('Use engineGetContactsResponseDescriptor instead')
const EngineGetContactsResponse$json = {
  '1': 'EngineGetContactsResponse',
  '2': [
    {'1': 'contacts', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineContactInfo', '10': 'contacts'},
  ],
};

/// Descriptor for `EngineGetContactsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetContactsResponseDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVHZXRDb250YWN0c1Jlc3BvbnNlEjgKCGNvbnRhY3RzGAEgAygLMhwudW5pY2xpZW'
    '50LkVuZ2luZUNvbnRhY3RJbmZvUghjb250YWN0cw==');

@$core.Deprecated('Use engineGetOnlineCountRequestDescriptor instead')
const EngineGetOnlineCountRequest$json = {
  '1': 'EngineGetOnlineCountRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineGetOnlineCountRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetOnlineCountRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVHZXRPbmxpbmVDb3VudFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZA==');

@$core.Deprecated('Use engineGetOnlineCountResponseDescriptor instead')
const EngineGetOnlineCountResponse$json = {
  '1': 'EngineGetOnlineCountResponse',
  '2': [
    {'1': 'online_count', '3': 1, '4': 1, '5': 5, '10': 'onlineCount'},
  ],
};

/// Descriptor for `EngineGetOnlineCountResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetOnlineCountResponseDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVHZXRPbmxpbmVDb3VudFJlc3BvbnNlEiEKDG9ubGluZV9jb3VudBgBIAEoBVILb2'
    '5saW5lQ291bnQ=');

@$core.Deprecated('Use engineGroupCallParticipantDescriptor instead')
const EngineGroupCallParticipant$json = {
  '1': 'EngineGroupCallParticipant',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'is_muted', '3': 3, '4': 1, '5': 8, '10': 'isMuted'},
    {'1': 'is_speaking', '3': 4, '4': 1, '5': 8, '10': 'isSpeaking'},
    {'1': 'has_video', '3': 5, '4': 1, '5': 8, '10': 'hasVideo'},
    {'1': 'avatar_path', '3': 6, '4': 1, '5': 9, '10': 'avatarPath'},
  ],
};

/// Descriptor for `EngineGroupCallParticipant`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGroupCallParticipantDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVHcm91cENhbGxQYXJ0aWNpcGFudBIXCgd1c2VyX2lkGAEgASgJUgZ1c2VySWQSIQ'
    'oMZGlzcGxheV9uYW1lGAIgASgJUgtkaXNwbGF5TmFtZRIZCghpc19tdXRlZBgDIAEoCFIHaXNN'
    'dXRlZBIfCgtpc19zcGVha2luZxgEIAEoCFIKaXNTcGVha2luZxIbCgloYXNfdmlkZW8YBSABKA'
    'hSCGhhc1ZpZGVvEh8KC2F2YXRhcl9wYXRoGAYgASgJUgphdmF0YXJQYXRo');

@$core.Deprecated('Use engineGroupCallInfoDescriptor instead')
const EngineGroupCallInfo$json = {
  '1': 'EngineGroupCallInfo',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 9, '10': 'callId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {'1': 'participants_count', '3': 4, '4': 1, '5': 5, '10': 'participantsCount'},
    {'1': 'participants', '3': 5, '4': 3, '5': 11, '6': '.uniclient.EngineGroupCallParticipant', '10': 'participants'},
    {'1': 'active', '3': 6, '4': 1, '5': 8, '10': 'active'},
  ],
};

/// Descriptor for `EngineGroupCallInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGroupCallInfoDescriptor = $convert.base64Decode(
    'ChNFbmdpbmVHcm91cENhbGxJbmZvEhcKB2NhbGxfaWQYASABKAlSBmNhbGxJZBIXCgdjaGF0X2'
    'lkGAIgASgJUgZjaGF0SWQSFAoFdGl0bGUYAyABKAlSBXRpdGxlEi0KEnBhcnRpY2lwYW50c19j'
    'b3VudBgEIAEoBVIRcGFydGljaXBhbnRzQ291bnQSSQoMcGFydGljaXBhbnRzGAUgAygLMiUudW'
    '5pY2xpZW50LkVuZ2luZUdyb3VwQ2FsbFBhcnRpY2lwYW50UgxwYXJ0aWNpcGFudHMSFgoGYWN0'
    'aXZlGAYgASgIUgZhY3RpdmU=');

@$core.Deprecated('Use engineGetGroupCallRequestDescriptor instead')
const EngineGetGroupCallRequest$json = {
  '1': 'EngineGetGroupCallRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineGetGroupCallRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetGroupCallRequestDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVHZXRHcm91cENhbGxSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bn'
    'RJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQ=');

@$core.Deprecated('Use engineGetGroupCallResponseDescriptor instead')
const EngineGetGroupCallResponse$json = {
  '1': 'EngineGetGroupCallResponse',
  '2': [
    {'1': 'group_call', '3': 1, '4': 1, '5': 11, '6': '.uniclient.EngineGroupCallInfo', '10': 'groupCall'},
  ],
};

/// Descriptor for `EngineGetGroupCallResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetGroupCallResponseDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVHZXRHcm91cENhbGxSZXNwb25zZRI9Cgpncm91cF9jYWxsGAEgASgLMh4udW5pY2'
    'xpZW50LkVuZ2luZUdyb3VwQ2FsbEluZm9SCWdyb3VwQ2FsbA==');

@$core.Deprecated('Use engineJoinGroupCallRequestDescriptor instead')
const EngineJoinGroupCallRequest$json = {
  '1': 'EngineJoinGroupCallRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineJoinGroupCallRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineJoinGroupCallRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVKb2luR3JvdXBDYWxsUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElk');

@$core.Deprecated('Use engineJoinGroupCallResponseDescriptor instead')
const EngineJoinGroupCallResponse$json = {
  '1': 'EngineJoinGroupCallResponse',
  '2': [
    {'1': 'call_id', '3': 1, '4': 1, '5': 9, '10': 'callId'},
  ],
};

/// Descriptor for `EngineJoinGroupCallResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineJoinGroupCallResponseDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVKb2luR3JvdXBDYWxsUmVzcG9uc2USFwoHY2FsbF9pZBgBIAEoCVIGY2FsbElk');

@$core.Deprecated('Use engineSendScheduledNowRequestDescriptor instead')
const EngineSendScheduledNowRequest$json = {
  '1': 'EngineSendScheduledNowRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_ids', '3': 3, '4': 3, '5': 9, '10': 'msgIds'},
  ],
};

/// Descriptor for `EngineSendScheduledNowRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSendScheduledNowRequestDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVTZW5kU2NoZWR1bGVkTm93UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2'
    'NvdW50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhcKB21zZ19pZHMYAyADKAlSBm1zZ0lk'
    'cw==');

@$core.Deprecated('Use engineRescheduleMessageRequestDescriptor instead')
const EngineRescheduleMessageRequest$json = {
  '1': 'EngineRescheduleMessageRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'schedule_date', '3': 4, '4': 1, '5': 3, '10': 'scheduleDate'},
  ],
};

/// Descriptor for `EngineRescheduleMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineRescheduleMessageRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVSZXNjaGVkdWxlTWVzc2FnZVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lk'
    'EiMKDXNjaGVkdWxlX2RhdGUYBCABKANSDHNjaGVkdWxlRGF0ZQ==');

@$core.Deprecated('Use enginePeerColorEntryDescriptor instead')
const EnginePeerColorEntry$json = {
  '1': 'EnginePeerColorEntry',
  '2': [
    {'1': 'color_id', '3': 1, '4': 1, '5': 5, '10': 'colorId'},
    {'1': 'day_colors', '3': 2, '4': 3, '5': 5, '10': 'dayColors'},
    {'1': 'night_colors', '3': 3, '4': 3, '5': 5, '10': 'nightColors'},
    {'1': 'hidden', '3': 4, '4': 1, '5': 8, '10': 'hidden'},
  ],
};

/// Descriptor for `EnginePeerColorEntry`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List enginePeerColorEntryDescriptor = $convert.base64Decode(
    'ChRFbmdpbmVQZWVyQ29sb3JFbnRyeRIZCghjb2xvcl9pZBgBIAEoBVIHY29sb3JJZBIdCgpkYX'
    'lfY29sb3JzGAIgAygFUglkYXlDb2xvcnMSIQoMbmlnaHRfY29sb3JzGAMgAygFUgtuaWdodENv'
    'bG9ycxIWCgZoaWRkZW4YBCABKAhSBmhpZGRlbg==');

@$core.Deprecated('Use engineGetPeerColorsRequestDescriptor instead')
const EngineGetPeerColorsRequest$json = {
  '1': 'EngineGetPeerColorsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetPeerColorsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetPeerColorsRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVHZXRQZWVyQ29sb3JzUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQ=');

@$core.Deprecated('Use engineGetPeerColorsResponseDescriptor instead')
const EngineGetPeerColorsResponse$json = {
  '1': 'EngineGetPeerColorsResponse',
  '2': [
    {'1': 'colors', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EnginePeerColorEntry', '10': 'colors'},
  ],
};

/// Descriptor for `EngineGetPeerColorsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetPeerColorsResponseDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVHZXRQZWVyQ29sb3JzUmVzcG9uc2USNwoGY29sb3JzGAEgAygLMh8udW5pY2xpZW'
    '50LkVuZ2luZVBlZXJDb2xvckVudHJ5UgZjb2xvcnM=');

@$core.Deprecated('Use engineGetStickerSetInfoRequestDescriptor instead')
const EngineGetStickerSetInfoRequest$json = {
  '1': 'EngineGetStickerSetInfoRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'short_name', '3': 2, '4': 1, '5': 9, '10': 'shortName'},
    {'1': 'set_id', '3': 3, '4': 1, '5': 3, '10': 'setId'},
    {'1': 'access_hash', '3': 4, '4': 1, '5': 3, '10': 'accessHash'},
  ],
};

/// Descriptor for `EngineGetStickerSetInfoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetStickerSetInfoRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVHZXRTdGlja2VyU2V0SW5mb1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElkEh0KCnNob3J0X25hbWUYAiABKAlSCXNob3J0TmFtZRIVCgZzZXRfaWQYAyABKANS'
    'BXNldElkEh8KC2FjY2Vzc19oYXNoGAQgASgDUgphY2Nlc3NIYXNo');

@$core.Deprecated('Use engineStickerInfoDescriptor instead')
const EngineStickerInfo$json = {
  '1': 'EngineStickerInfo',
  '2': [
    {'1': 'emoji', '3': 1, '4': 1, '5': 9, '10': 'emoji'},
    {'1': 'thumb_b64', '3': 2, '4': 1, '5': 9, '10': 'thumbB64'},
    {'1': 'width', '3': 3, '4': 1, '5': 5, '10': 'width'},
    {'1': 'height', '3': 4, '4': 1, '5': 5, '10': 'height'},
    {'1': 'mime_type', '3': 5, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'file_id', '3': 6, '4': 1, '5': 9, '10': 'fileId'},
  ],
};

/// Descriptor for `EngineStickerInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineStickerInfoDescriptor = $convert.base64Decode(
    'ChFFbmdpbmVTdGlja2VySW5mbxIUCgVlbW9qaRgBIAEoCVIFZW1vamkSGwoJdGh1bWJfYjY0GA'
    'IgASgJUgh0aHVtYkI2NBIUCgV3aWR0aBgDIAEoBVIFd2lkdGgSFgoGaGVpZ2h0GAQgASgFUgZo'
    'ZWlnaHQSGwoJbWltZV90eXBlGAUgASgJUghtaW1lVHlwZRIXCgdmaWxlX2lkGAYgASgJUgZmaW'
    'xlSWQ=');

@$core.Deprecated('Use engineGetStickerSetInfoResponseDescriptor instead')
const EngineGetStickerSetInfoResponse$json = {
  '1': 'EngineGetStickerSetInfoResponse',
  '2': [
    {'1': 'title', '3': 1, '4': 1, '5': 9, '10': 'title'},
    {'1': 'short_name', '3': 2, '4': 1, '5': 9, '10': 'shortName'},
    {'1': 'count', '3': 3, '4': 1, '5': 5, '10': 'count'},
    {'1': 'installed', '3': 4, '4': 1, '5': 8, '10': 'installed'},
    {'1': 'archived', '3': 5, '4': 1, '5': 8, '10': 'archived'},
    {'1': 'animated', '3': 6, '4': 1, '5': 8, '10': 'animated'},
    {'1': 'video', '3': 7, '4': 1, '5': 8, '10': 'video'},
    {'1': 'stickers', '3': 8, '4': 3, '5': 11, '6': '.uniclient.EngineStickerInfo', '10': 'stickers'},
  ],
};

/// Descriptor for `EngineGetStickerSetInfoResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetStickerSetInfoResponseDescriptor = $convert.base64Decode(
    'Ch9FbmdpbmVHZXRTdGlja2VyU2V0SW5mb1Jlc3BvbnNlEhQKBXRpdGxlGAEgASgJUgV0aXRsZR'
    'IdCgpzaG9ydF9uYW1lGAIgASgJUglzaG9ydE5hbWUSFAoFY291bnQYAyABKAVSBWNvdW50EhwK'
    'CWluc3RhbGxlZBgEIAEoCFIJaW5zdGFsbGVkEhoKCGFyY2hpdmVkGAUgASgIUghhcmNoaXZlZB'
    'IaCghhbmltYXRlZBgGIAEoCFIIYW5pbWF0ZWQSFAoFdmlkZW8YByABKAhSBXZpZGVvEjgKCHN0'
    'aWNrZXJzGAggAygLMhwudW5pY2xpZW50LkVuZ2luZVN0aWNrZXJJbmZvUghzdGlja2Vycw==');

@$core.Deprecated('Use engineTranscribeAudioRequestDescriptor instead')
const EngineTranscribeAudioRequest$json = {
  '1': 'EngineTranscribeAudioRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
  ],
};

/// Descriptor for `EngineTranscribeAudioRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineTranscribeAudioRequestDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVUcmFuc2NyaWJlQXVkaW9SZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY2'
    '91bnRJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSFQoGbXNnX2lkGAMgASgJUgVtc2dJZA==');

@$core.Deprecated('Use engineTranscribeAudioResponseDescriptor instead')
const EngineTranscribeAudioResponse$json = {
  '1': 'EngineTranscribeAudioResponse',
  '2': [
    {'1': 'pending', '3': 1, '4': 1, '5': 8, '10': 'pending'},
    {'1': 'transcription_id', '3': 2, '4': 1, '5': 3, '10': 'transcriptionId'},
    {'1': 'text', '3': 3, '4': 1, '5': 9, '10': 'text'},
  ],
};

/// Descriptor for `EngineTranscribeAudioResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineTranscribeAudioResponseDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVUcmFuc2NyaWJlQXVkaW9SZXNwb25zZRIYCgdwZW5kaW5nGAEgASgIUgdwZW5kaW'
    '5nEikKEHRyYW5zY3JpcHRpb25faWQYAiABKANSD3RyYW5zY3JpcHRpb25JZBISCgR0ZXh0GAMg'
    'ASgJUgR0ZXh0');

@$core.Deprecated('Use engineGetAttachMenuBotsRequestDescriptor instead')
const EngineGetAttachMenuBotsRequest$json = {
  '1': 'EngineGetAttachMenuBotsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetAttachMenuBotsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetAttachMenuBotsRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVHZXRBdHRhY2hNZW51Qm90c1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElk');

@$core.Deprecated('Use engineAttachMenuBotInfoDescriptor instead')
const EngineAttachMenuBotInfo$json = {
  '1': 'EngineAttachMenuBotInfo',
  '2': [
    {'1': 'bot_id', '3': 1, '4': 1, '5': 3, '10': 'botId'},
    {'1': 'short_name', '3': 2, '4': 1, '5': 9, '10': 'shortName'},
    {'1': 'inactive', '3': 3, '4': 1, '5': 8, '10': 'inactive'},
    {'1': 'username', '3': 4, '4': 1, '5': 9, '10': 'username'},
  ],
};

/// Descriptor for `EngineAttachMenuBotInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineAttachMenuBotInfoDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVBdHRhY2hNZW51Qm90SW5mbxIVCgZib3RfaWQYASABKANSBWJvdElkEh0KCnNob3J0'
    'X25hbWUYAiABKAlSCXNob3J0TmFtZRIaCghpbmFjdGl2ZRgDIAEoCFIIaW5hY3RpdmUSGgoIdXNl'
    'cm5hbWUYBCABKAlSCHVzZXJuYW1l');

@$core.Deprecated('Use engineGetAttachMenuBotsResponseDescriptor instead')
const EngineGetAttachMenuBotsResponse$json = {
  '1': 'EngineGetAttachMenuBotsResponse',
  '2': [
    {'1': 'bots', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineAttachMenuBotInfo', '10': 'bots'},
  ],
};

/// Descriptor for `EngineGetAttachMenuBotsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetAttachMenuBotsResponseDescriptor = $convert.base64Decode(
    'Ch9FbmdpbmVHZXRBdHRhY2hNZW51Qm90c1Jlc3BvbnNlEjYKBGJvdHMYASADKAsyIi51bmljbG'
    'llbnQuRW5naW5lQXR0YWNoTWVudUJvdEluZm9SBGJvdHM=');

@$core.Deprecated('Use engineGetWebPagePreviewRequestDescriptor instead')
const EngineGetWebPagePreviewRequest$json = {
  '1': 'EngineGetWebPagePreviewRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'url', '3': 2, '4': 1, '5': 9, '10': 'url'},
  ],
};

/// Descriptor for `EngineGetWebPagePreviewRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetWebPagePreviewRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVHZXRXZWJQYWdlUHJldmlld1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElkEhAKA3VybBgCIAEoCVIDdXJs');

@$core.Deprecated('Use engineGetWebPagePreviewResponseDescriptor instead')
const EngineGetWebPagePreviewResponse$json = {
  '1': 'EngineGetWebPagePreviewResponse',
  '2': [
    {'1': 'url', '3': 1, '4': 1, '5': 9, '10': 'url'},
    {'1': 'site_name', '3': 2, '4': 1, '5': 9, '10': 'siteName'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {'1': 'description', '3': 4, '4': 1, '5': 9, '10': 'description'},
    {'1': 'thumb_b64', '3': 5, '4': 1, '5': 9, '10': 'thumbB64'},
    {'1': 'type', '3': 6, '4': 1, '5': 9, '10': 'type'},
    {'1': 'has_large_media', '3': 7, '4': 1, '5': 8, '10': 'hasLargeMedia'},
    {'1': 'pending_till', '3': 8, '4': 1, '5': 3, '10': 'pendingTill'},
  ],
};

/// Descriptor for `EngineGetWebPagePreviewResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetWebPagePreviewResponseDescriptor = $convert.base64Decode(
    'Ch9FbmdpbmVHZXRXZWJQYWdlUHJldmlld1Jlc3BvbnNlEhAKA3VybBgBIAEoCVIDdXJsEhsKCX'
    'NpdGVfbmFtZRgCIAEoCVIIc2l0ZU5hbWUSFAoFdGl0bGUYAyABKAlSBXRpdGxlEiAKC2Rlc2Ny'
    'aXB0aW9uGAQgASgJUgtkZXNjcmlwdGlvbhIbCgl0aHVtYl9iNjQYBSABKAlSCHRodW1iQjY0Eh'
    'IKBHR5cGUYBiABKAlSBHR5cGUSJgoPaGFzX2xhcmdlX21lZGlhGAcgASgIUg1oYXNMYXJnZU1l'
    'ZGlhEiEKDHBlbmRpbmdfdGlsbBgIIAEoA1ILcGVuZGluZ1RpbGw=');

@$core.Deprecated('Use engineBotCallbackRequestDescriptor instead')
const EngineBotCallbackRequest$json = {
  '1': 'EngineBotCallbackRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'data', '3': 4, '4': 1, '5': 9, '10': 'data'},
  ],
};

/// Descriptor for `EngineBotCallbackRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineBotCallbackRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVCb3RDYWxsYmFja1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lkEhIKBGRh'
    'dGEYBCABKAlSBGRhdGE=');

@$core.Deprecated('Use engineBotCallbackResponseDescriptor instead')
const EngineBotCallbackResponse$json = {
  '1': 'EngineBotCallbackResponse',
  '2': [
    {'1': 'message', '3': 1, '4': 1, '5': 9, '10': 'message'},
    {'1': 'show_alert', '3': 2, '4': 1, '5': 8, '10': 'showAlert'},
    {'1': 'url', '3': 3, '4': 1, '5': 9, '10': 'url'},
  ],
};

/// Descriptor for `EngineBotCallbackResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineBotCallbackResponseDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVCb3RDYWxsYmFja1Jlc3BvbnNlEhgKB21lc3NhZ2UYASABKAlSB21lc3NhZ2USHQ'
    'oKc2hvd19hbGVydBgCIAEoCFIJc2hvd0FsZXJ0EhAKA3VybBgDIAEoCVIDdXJs');

@$core.Deprecated('Use engineGetSendAsRequestDescriptor instead')
const EngineGetSendAsRequest$json = {
  '1': 'EngineGetSendAsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
  ],
};

/// Descriptor for `EngineGetSendAsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSendAsRequestDescriptor = $convert.base64Decode(
    'ChZFbmdpbmVHZXRTZW5kQXNSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bnRJZB'
    'IXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQ=');

@$core.Deprecated('Use engineSendAsPeerInfoDescriptor instead')
const EngineSendAsPeerInfo$json = {
  '1': 'EngineSendAsPeerInfo',
  '2': [
    {'1': 'peer_id', '3': 1, '4': 1, '5': 9, '10': 'peerId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'avatar_path', '3': 3, '4': 1, '5': 9, '10': 'avatarPath'},
    {'1': 'is_channel', '3': 4, '4': 1, '5': 8, '10': 'isChannel'},
  ],
};

/// Descriptor for `EngineSendAsPeerInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSendAsPeerInfoDescriptor = $convert.base64Decode(
    'ChRFbmdpbmVTZW5kQXNQZWVySW5mbxIXCgdwZWVyX2lkGAEgASgJUgZwZWVySWQSIQoMZGlzcG'
    'xheV9uYW1lGAIgASgJUgtkaXNwbGF5TmFtZRIfCgthdmF0YXJfcGF0aBgDIAEoCVIKYXZhdGFy'
    'UGF0aBIdCgppc19jaGFubmVsGAQgASgIUglpc0NoYW5uZWw=');

@$core.Deprecated('Use engineGetSendAsResponseDescriptor instead')
const EngineGetSendAsResponse$json = {
  '1': 'EngineGetSendAsResponse',
  '2': [
    {'1': 'peers', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineSendAsPeerInfo', '10': 'peers'},
  ],
};

/// Descriptor for `EngineGetSendAsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSendAsResponseDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVHZXRTZW5kQXNSZXNwb25zZRI1CgVwZWVycxgBIAMoCzIfLnVuaWNsaWVudC5Fbm'
    'dpbmVTZW5kQXNQZWVySW5mb1IFcGVlcnM=');

@$core.Deprecated('Use engineSaveDefaultSendAsRequestDescriptor instead')
const EngineSaveDefaultSendAsRequest$json = {
  '1': 'EngineSaveDefaultSendAsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'peer_id', '3': 3, '4': 1, '5': 9, '10': 'peerId'},
  ],
};

/// Descriptor for `EngineSaveDefaultSendAsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSaveDefaultSendAsRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVTYXZlRGVmYXVsdFNlbmRBc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIXCgdwZWVyX2lkGAMgASgJUgZwZWVy'
    'SWQ=');

@$core.Deprecated('Use engineSaveDefaultSendAsResponseDescriptor instead')
const EngineSaveDefaultSendAsResponse$json = {
  '1': 'EngineSaveDefaultSendAsResponse',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
  ],
};

/// Descriptor for `EngineSaveDefaultSendAsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSaveDefaultSendAsResponseDescriptor = $convert.base64Decode(
    'Ch9FbmdpbmVTYXZlRGVmYXVsdFNlbmRBc1Jlc3BvbnNlEg4KAm9rGAEgASgIUgJvaw==');

@$core.Deprecated('Use engineBanMemberRequestDescriptor instead')
const EngineBanMemberRequest$json = {
  '1': 'EngineBanMemberRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'user_id', '3': 3, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `EngineBanMemberRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineBanMemberRequestDescriptor = $convert.base64Decode(
    'ChZFbmdpbmVCYW5NZW1iZXJSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bnRJZB'
    'IXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSFwoHdXNlcl9pZBgDIAEoCVIGdXNlcklk');

@$core.Deprecated('Use engineRemoveMemberRequestDescriptor instead')
const EngineRemoveMemberRequest$json = {
  '1': 'EngineRemoveMemberRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'user_id', '3': 3, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `EngineRemoveMemberRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineRemoveMemberRequestDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVSZW1vdmVNZW1iZXJSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bn'
    'RJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSFwoHdXNlcl9pZBgDIAEoCVIGdXNlcklk');

@$core.Deprecated('Use engineDemoteAdminRequestDescriptor instead')
const EngineDemoteAdminRequest$json = {
  '1': 'EngineDemoteAdminRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'user_id', '3': 3, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `EngineDemoteAdminRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineDemoteAdminRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVEZW1vdGVBZG1pblJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIXCgd1c2VyX2lkGAMgASgJUgZ1c2VySWQ=');

@$core.Deprecated('Use enginePromoteAdminRequestDescriptor instead')
const EnginePromoteAdminRequest$json = {
  '1': 'EnginePromoteAdminRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'user_id', '3': 3, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `EnginePromoteAdminRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List enginePromoteAdminRequestDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVQcm9tb3RlQWRtaW5SZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bn'
    'RJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSFwoHdXNlcl9pZBgDIAEoCVIGdXNlcklk');

@$core.Deprecated('Use engineRestrictMemberRequestDescriptor instead')
const EngineRestrictMemberRequest$json = {
  '1': 'EngineRestrictMemberRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'user_id', '3': 3, '4': 1, '5': 9, '10': 'userId'},
  ],
};

/// Descriptor for `EngineRestrictMemberRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineRestrictMemberRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVSZXN0cmljdE1lbWJlclJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIXCgd1c2VyX2lkGAMgASgJUgZ1c2VySWQ=');

@$core.Deprecated('Use engineFaveStickerRequestDescriptor instead')
const EngineFaveStickerRequest$json = {
  '1': 'EngineFaveStickerRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'file_id', '3': 2, '4': 1, '5': 3, '10': 'fileId'},
    {'1': 'unfave', '3': 3, '4': 1, '5': 8, '10': 'unfave'},
    {'1': 'extra', '3': 4, '4': 1, '5': 9, '10': 'extra'},
  ],
};

/// Descriptor for `EngineFaveStickerRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineFaveStickerRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVGYXZlU3RpY2tlclJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2ZpbGVfaWQYAiABKANSBmZpbGVJZBIWCgZ1bmZhdmUYAyABKAhSBnVuZmF2ZRIUCgVl'
    'eHRyYRgEIAEoCVIFZXh0cmE=');

@$core.Deprecated('Use engineSaveGifRequestDescriptor instead')
const EngineSaveGifRequest$json = {
  '1': 'EngineSaveGifRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'file_id', '3': 2, '4': 1, '5': 3, '10': 'fileId'},
    {'1': 'unsave', '3': 3, '4': 1, '5': 8, '10': 'unsave'},
    {'1': 'extra', '3': 4, '4': 1, '5': 9, '10': 'extra'},
  ],
};

/// Descriptor for `EngineSaveGifRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSaveGifRequestDescriptor = $convert.base64Decode(
    'ChRFbmdpbmVTYXZlR2lmUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SWQSFw'
    'oHZmlsZV9pZBgCIAEoA1IGZmlsZUlkEhYKBnVuc2F2ZRgDIAEoCFIGdW5zYXZlEhQKBWV4dHJh'
    'GAQgASgJUgVleHRyYQ==');

@$core.Deprecated('Use engineGifInfoDescriptor instead')
const EngineGifInfo$json = {
  '1': 'EngineGifInfo',
  '2': [
    {'1': 'thumb_b64', '3': 1, '4': 1, '5': 9, '10': 'thumbB64'},
    {'1': 'width', '3': 2, '4': 1, '5': 5, '10': 'width'},
    {'1': 'height', '3': 3, '4': 1, '5': 5, '10': 'height'},
    {'1': 'mime_type', '3': 4, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'file_id', '3': 5, '4': 1, '5': 9, '10': 'fileId'},
  ],
};

/// Descriptor for `EngineGifInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGifInfoDescriptor = $convert.base64Decode(
    'Cg1FbmdpbmVHaWZJbmZvEhsKCXRodW1iX2I2NBgBIAEoCVIIdGh1bWJCNjQSFAoFd2lkdGgYAi'
    'ABKAVSBXdpZHRoEhYKBmhlaWdodBgDIAEoBVIGaGVpZ2h0EhsKCW1pbWVfdHlwZRgEIAEoCVII'
    'bWltZVR5cGUSFwoHZmlsZV9pZBgFIAEoCVIGZmlsZUlk');

@$core.Deprecated('Use engineGetSavedGifsRequestDescriptor instead')
const EngineGetSavedGifsRequest$json = {
  '1': 'EngineGetSavedGifsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetSavedGifsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSavedGifsRequestDescriptor = $convert.base64Decode(
    'ChlFbmdpbmVHZXRTYXZlZEdpZnNSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY291bn'
    'RJZA==');

@$core.Deprecated('Use engineGetSavedGifsResponseDescriptor instead')
const EngineGetSavedGifsResponse$json = {
  '1': 'EngineGetSavedGifsResponse',
  '2': [
    {'1': 'gifs', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineGifInfo', '10': 'gifs'},
  ],
};

/// Descriptor for `EngineGetSavedGifsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSavedGifsResponseDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVHZXRTYXZlZEdpZnNSZXNwb25zZRIsCgRnaWZzGAEgAygLMhgudW5pY2xpZW50Lk'
    'VuZ2luZUdpZkluZm9SBGdpZnM=');

@$core.Deprecated('Use engineTranslateTextRequestDescriptor instead')
const EngineTranslateTextRequest$json = {
  '1': 'EngineTranslateTextRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'to_lang', '3': 4, '4': 1, '5': 9, '10': 'toLang'},
    {'1': 'text', '3': 5, '4': 1, '5': 9, '10': 'text'},
  ],
};

/// Descriptor for `EngineTranslateTextRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineTranslateTextRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVUcmFuc2xhdGVUZXh0UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhUKBm1zZ19pZBgDIAEoCVIFbXNnSWQSFwoH'
    'dG9fbGFuZxgEIAEoCVIGdG9MYW5nEhIKBHRleHQYBSABKAlSBHRleHQ=');

@$core.Deprecated('Use engineTranslateTextResponseDescriptor instead')
const EngineTranslateTextResponse$json = {
  '1': 'EngineTranslateTextResponse',
  '2': [
    {'1': 'translated_text', '3': 1, '4': 1, '5': 9, '10': 'translatedText'},
  ],
};

/// Descriptor for `EngineTranslateTextResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineTranslateTextResponseDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVUcmFuc2xhdGVUZXh0UmVzcG9uc2USJwoPdHJhbnNsYXRlZF90ZXh0GAEgASgJUg'
    '50cmFuc2xhdGVkVGV4dA==');

@$core.Deprecated('Use engineReportMessageRequestDescriptor instead')
const EngineReportMessageRequest$json = {
  '1': 'EngineReportMessageRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_ids', '3': 3, '4': 3, '5': 5, '10': 'msgIds'},
    {'1': 'option', '3': 4, '4': 1, '5': 12, '10': 'option'},
    {'1': 'message', '3': 5, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `EngineReportMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineReportMessageRequestDescriptor = $convert.base64Decode(
    'ChpFbmdpbmVSZXBvcnRNZXNzYWdlUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW'
    '50SWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhcKB21zZ19pZHMYAyADKAVSBm1zZ0lkcxIW'
    'CgZvcHRpb24YBCABKAxSBm9wdGlvbhIYCgdtZXNzYWdlGAUgASgJUgdtZXNzYWdl');

@$core.Deprecated('Use engineReportMessageResponseDescriptor instead')
const EngineReportMessageResponse$json = {
  '1': 'EngineReportMessageResponse',
  '2': [
    {'1': 'result_type', '3': 1, '4': 1, '5': 9, '10': 'resultType'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'options', '3': 3, '4': 3, '5': 11, '6': '.uniclient.ReportOption', '10': 'options'},
    {'1': 'comment_optional', '3': 4, '4': 1, '5': 8, '10': 'commentOptional'},
    {'1': 'comment_option', '3': 5, '4': 1, '5': 12, '10': 'commentOption'},
  ],
};

/// Descriptor for `EngineReportMessageResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineReportMessageResponseDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVSZXBvcnRNZXNzYWdlUmVzcG9uc2USHwoLcmVzdWx0X3R5cGUYASABKAlSCnJlc3'
    'VsdFR5cGUSFAoFdGl0bGUYAiABKAlSBXRpdGxlEjEKB29wdGlvbnMYAyADKAsyFy51bmljbGll'
    'bnQuUmVwb3J0T3B0aW9uUgdvcHRpb25zEikKEGNvbW1lbnRfb3B0aW9uYWwYBCABKAhSD2NvbW'
    '1lbnRPcHRpb25hbBIlCg5jb21tZW50X29wdGlvbhgFIAEoDFINY29tbWVudE9wdGlvbg==');

@$core.Deprecated('Use reportOptionDescriptor instead')
const ReportOption$json = {
  '1': 'ReportOption',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'option', '3': 2, '4': 1, '5': 12, '10': 'option'},
  ],
};

/// Descriptor for `ReportOption`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reportOptionDescriptor = $convert.base64Decode(
    'CgxSZXBvcnRPcHRpb24SEgoEdGV4dBgBIAEoCVIEdGV4dBIWCgZvcHRpb24YAiABKAxSBm9wdG'
    'lvbg==');

@$core.Deprecated('Use engineVotePollRequestDescriptor instead')
const EngineVotePollRequest$json = {
  '1': 'EngineVotePollRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'option_index', '3': 4, '4': 1, '5': 5, '10': 'optionIndex'},
  ],
};

/// Descriptor for `EngineVotePollRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineVotePollRequestDescriptor = $convert.base64Decode(
    'ChVFbmdpbmVWb3RlUG9sbFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudElkEh'
    'cKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lkEiEKDG9wdGlv'
    'bl9pbmRleBgEIAEoBVILb3B0aW9uSW5kZXg=');

@$core.Deprecated('Use engineRetractPollVoteRequestDescriptor instead')
const EngineRetractPollVoteRequest$json = {
  '1': 'EngineRetractPollVoteRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
  ],
};

/// Descriptor for `EngineRetractPollVoteRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineRetractPollVoteRequestDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVSZXRyYWN0UG9sbFZvdGVSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY2'
    '91bnRJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSFQoGbXNnX2lkGAMgASgJUgVtc2dJZA==');

@$core.Deprecated('Use engineStopPollRequestDescriptor instead')
const EngineStopPollRequest$json = {
  '1': 'EngineStopPollRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
  ],
};

/// Descriptor for `EngineStopPollRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineStopPollRequestDescriptor = $convert.base64Decode(
    'ChVFbmdpbmVTdG9wUG9sbFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudElkEh'
    'cKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lk');

@$core.Deprecated('Use engineGetInstalledEmojiSetsRequestDescriptor instead')
const EngineGetInstalledEmojiSetsRequest$json = {
  '1': 'EngineGetInstalledEmojiSetsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetInstalledEmojiSetsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetInstalledEmojiSetsRequestDescriptor = $convert.base64Decode(
    'CiJFbmdpbmVHZXRJbnN0YWxsZWRFbW9qaVNldHNSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKA'
    'lSCWFjY291bnRJZA==');

@$core.Deprecated('Use engineEmojiSetSummaryDescriptor instead')
const EngineEmojiSetSummary$json = {
  '1': 'EngineEmojiSetSummary',
  '2': [
    {'1': 'set_id', '3': 1, '4': 1, '5': 3, '10': 'setId'},
    {'1': 'access_hash', '3': 2, '4': 1, '5': 3, '10': 'accessHash'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {'1': 'short_name', '3': 4, '4': 1, '5': 9, '10': 'shortName'},
    {'1': 'count', '3': 5, '4': 1, '5': 5, '10': 'count'},
    {'1': 'installed', '3': 6, '4': 1, '5': 8, '10': 'installed'},
    {'1': 'premium', '3': 7, '4': 1, '5': 8, '10': 'premium'},
    {'1': 'stickers', '3': 8, '4': 3, '5': 11, '6': '.uniclient.EngineStickerInfo', '10': 'stickers'},
  ],
};

/// Descriptor for `EngineEmojiSetSummary`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineEmojiSetSummaryDescriptor = $convert.base64Decode(
    'ChVFbmdpbmVFbW9qaVNldFN1bW1hcnkSFQoGc2V0X2lkGAEgASgDUgVzZXRJZBIfCgthY2Nlc3'
    'NfaGFzaBgCIAEoA1IKYWNjZXNzSGFzaBIUCgV0aXRsZRgDIAEoCVIFdGl0bGUSHQoKc2hvcnRf'
    'bmFtZRgEIAEoCVIJc2hvcnROYW1lEhQKBWNvdW50GAUgASgFUgVjb3VudBIcCglpbnN0YWxsZW'
    'QYBiABKAhSCWluc3RhbGxlZBIYCgdwcmVtaXVtGAcgASgIUgdwcmVtaXVtEjgKCHN0aWNrZXJz'
    'GAggAygLMhwudW5pY2xpZW50LkVuZ2luZVN0aWNrZXJJbmZvUghzdGlja2Vycw==');

@$core.Deprecated('Use engineGetInstalledEmojiSetsResponseDescriptor instead')
const EngineGetInstalledEmojiSetsResponse$json = {
  '1': 'EngineGetInstalledEmojiSetsResponse',
  '2': [
    {'1': 'sets', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineEmojiSetSummary', '10': 'sets'},
  ],
};

/// Descriptor for `EngineGetInstalledEmojiSetsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetInstalledEmojiSetsResponseDescriptor = $convert.base64Decode(
    'CiNFbmdpbmVHZXRJbnN0YWxsZWRFbW9qaVNldHNSZXNwb25zZRI0CgRzZXRzGAEgAygLMiAudW'
    '5pY2xpZW50LkVuZ2luZUVtb2ppU2V0U3VtbWFyeVIEc2V0cw==');

@$core.Deprecated('Use engineGetInstalledStickerPacksRequestDescriptor instead')
const EngineGetInstalledStickerPacksRequest$json = {
  '1': 'EngineGetInstalledStickerPacksRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetInstalledStickerPacksRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetInstalledStickerPacksRequestDescriptor = $convert.base64Decode(
    'CiVFbmdpbmVHZXRJbnN0YWxsZWRTdGlja2VyUGFja3NSZXF1ZXN0Eh0KCmFjY291bnRfaWQYAS'
    'ABKAlSCWFjY291bnRJZA==');

@$core.Deprecated('Use engineStickerPackSummaryDescriptor instead')
const EngineStickerPackSummary$json = {
  '1': 'EngineStickerPackSummary',
  '2': [
    {'1': 'set_id', '3': 1, '4': 1, '5': 3, '10': 'setId'},
    {'1': 'access_hash', '3': 2, '4': 1, '5': 3, '10': 'accessHash'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {'1': 'short_name', '3': 4, '4': 1, '5': 9, '10': 'shortName'},
    {'1': 'count', '3': 5, '4': 1, '5': 5, '10': 'count'},
    {'1': 'animated', '3': 6, '4': 1, '5': 8, '10': 'animated'},
    {'1': 'video', '3': 7, '4': 1, '5': 8, '10': 'video'},
    {'1': 'thumb_b64', '3': 8, '4': 1, '5': 9, '10': 'thumbB64'},
    {'1': 'stickers', '3': 9, '4': 3, '5': 11, '6': '.uniclient.EngineStickerInfo', '10': 'stickers'},
    {'1': 'installed', '3': 10, '4': 1, '5': 8, '10': 'installed'},
  ],
};

/// Descriptor for `EngineStickerPackSummary`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineStickerPackSummaryDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVTdGlja2VyUGFja1N1bW1hcnkSFQoGc2V0X2lkGAEgASgDUgVzZXRJZBIfCgthY2'
    'Nlc3NfaGFzaBgCIAEoA1IKYWNjZXNzSGFzaBIUCgV0aXRsZRgDIAEoCVIFdGl0bGUSHQoKc2hv'
    'cnRfbmFtZRgEIAEoCVIJc2hvcnROYW1lEhQKBWNvdW50GAUgASgFUgVjb3VudBIaCghhbmltYX'
    'RlZBgGIAEoCFIIYW5pbWF0ZWQSFAoFdmlkZW8YByABKAhSBXZpZGVvEhsKCXRodW1iX2I2NBgI'
    'IAEoCVIIdGh1bWJCNjQSOAoIc3RpY2tlcnMYCSADKAsyHC51bmljbGllbnQuRW5naW5lU3RpY2'
    'tlckluZm9SCHN0aWNrZXJzEhwKCWluc3RhbGxlZBgKIAEoCFIJaW5zdGFsbGVk');

@$core.Deprecated('Use engineGetInstalledStickerPacksResponseDescriptor instead')
const EngineGetInstalledStickerPacksResponse$json = {
  '1': 'EngineGetInstalledStickerPacksResponse',
  '2': [
    {'1': 'packs', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineStickerPackSummary', '10': 'packs'},
  ],
};

/// Descriptor for `EngineGetInstalledStickerPacksResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetInstalledStickerPacksResponseDescriptor = $convert.base64Decode(
    'CiZFbmdpbmVHZXRJbnN0YWxsZWRTdGlja2VyUGFja3NSZXNwb25zZRI5CgVwYWNrcxgBIAMoCz'
    'IjLnVuaWNsaWVudC5FbmdpbmVTdGlja2VyUGFja1N1bW1hcnlSBXBhY2tz');

@$core.Deprecated('Use engineGetRecentStickersRequestDescriptor instead')
const EngineGetRecentStickersRequest$json = {
  '1': 'EngineGetRecentStickersRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetRecentStickersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetRecentStickersRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVHZXRSZWNlbnRTdGlja2Vyc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElk');

@$core.Deprecated('Use engineGetRecentStickersResponseDescriptor instead')
const EngineGetRecentStickersResponse$json = {
  '1': 'EngineGetRecentStickersResponse',
  '2': [
    {'1': 'stickers', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineStickerInfo', '10': 'stickers'},
  ],
};

/// Descriptor for `EngineGetRecentStickersResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetRecentStickersResponseDescriptor = $convert.base64Decode(
    'Ch9FbmdpbmVHZXRSZWNlbnRTdGlja2Vyc1Jlc3BvbnNlEjgKCHN0aWNrZXJzGAEgAygLMhwudW'
    '5pY2xpZW50LkVuZ2luZVN0aWNrZXJJbmZvUghzdGlja2Vycw==');

@$core.Deprecated('Use engineGetFeaturedStickerPacksRequestDescriptor instead')
const EngineGetFeaturedStickerPacksRequest$json = {
  '1': 'EngineGetFeaturedStickerPacksRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetFeaturedStickerPacksRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetFeaturedStickerPacksRequestDescriptor = $convert.base64Decode(
    'CiRFbmdpbmVHZXRGZWF0dXJlZFN0aWNrZXJQYWNrc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIA'
    'EoCVIJYWNjb3VudElk');

@$core.Deprecated('Use engineGetFeaturedStickerPacksResponseDescriptor instead')
const EngineGetFeaturedStickerPacksResponse$json = {
  '1': 'EngineGetFeaturedStickerPacksResponse',
  '2': [
    {'1': 'packs', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineStickerPackSummary', '10': 'packs'},
  ],
};

/// Descriptor for `EngineGetFeaturedStickerPacksResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetFeaturedStickerPacksResponseDescriptor = $convert.base64Decode(
    'CiVFbmdpbmVHZXRGZWF0dXJlZFN0aWNrZXJQYWNrc1Jlc3BvbnNlEjkKBXBhY2tzGAEgAygLMi'
    'MudW5pY2xpZW50LkVuZ2luZVN0aWNrZXJQYWNrU3VtbWFyeVIFcGFja3M=');

@$core.Deprecated('Use engineSearchStickerSetsRequestDescriptor instead')
const EngineSearchStickerSetsRequest$json = {
  '1': 'EngineSearchStickerSetsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'query', '3': 2, '4': 1, '5': 9, '10': 'query'},
  ],
};

/// Descriptor for `EngineSearchStickerSetsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSearchStickerSetsRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVTZWFyY2hTdGlja2VyU2V0c1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElkEhQKBXF1ZXJ5GAIgASgJUgVxdWVyeQ==');

@$core.Deprecated('Use engineSearchStickerSetsResponseDescriptor instead')
const EngineSearchStickerSetsResponse$json = {
  '1': 'EngineSearchStickerSetsResponse',
  '2': [
    {'1': 'packs', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineStickerPackSummary', '10': 'packs'},
  ],
};

/// Descriptor for `EngineSearchStickerSetsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSearchStickerSetsResponseDescriptor = $convert.base64Decode(
    'Ch9FbmdpbmVTZWFyY2hTdGlja2VyU2V0c1Jlc3BvbnNlEjkKBXBhY2tzGAEgAygLMiMudW5pY2'
    'xpZW50LkVuZ2luZVN0aWNrZXJQYWNrU3VtbWFyeVIFcGFja3M=');

@$core.Deprecated('Use engineInstallStickerSetRequestDescriptor instead')
const EngineInstallStickerSetRequest$json = {
  '1': 'EngineInstallStickerSetRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'set_id', '3': 2, '4': 1, '5': 3, '10': 'setId'},
    {'1': 'access_hash', '3': 3, '4': 1, '5': 3, '10': 'accessHash'},
  ],
};

/// Descriptor for `EngineInstallStickerSetRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineInstallStickerSetRequestDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVJbnN0YWxsU3RpY2tlclNldFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYW'
    'Njb3VudElkEhUKBnNldF9pZBgCIAEoA1IFc2V0SWQSHwoLYWNjZXNzX2hhc2gYAyABKANSCmFj'
    'Y2Vzc0hhc2g=');

@$core.Deprecated('Use engineInstallStickerSetResponseDescriptor instead')
const EngineInstallStickerSetResponse$json = {
  '1': 'EngineInstallStickerSetResponse',
};

/// Descriptor for `EngineInstallStickerSetResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineInstallStickerSetResponseDescriptor = $convert.base64Decode(
    'Ch9FbmdpbmVJbnN0YWxsU3RpY2tlclNldFJlc3BvbnNl');

@$core.Deprecated('Use engineGetStickerSuggestionsRequestDescriptor instead')
const EngineGetStickerSuggestionsRequest$json = {
  '1': 'EngineGetStickerSuggestionsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'emoji', '3': 2, '4': 1, '5': 9, '10': 'emoji'},
  ],
};

/// Descriptor for `EngineGetStickerSuggestionsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetStickerSuggestionsRequestDescriptor = $convert.base64Decode(
    'CiJFbmdpbmVHZXRTdGlja2VyU3VnZ2VzdGlvbnNSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKA'
    'lSCWFjY291bnRJZBIUCgVlbW9qaRgCIAEoCVIFZW1vamk=');

@$core.Deprecated('Use engineGetStickerSuggestionsResponseDescriptor instead')
const EngineGetStickerSuggestionsResponse$json = {
  '1': 'EngineGetStickerSuggestionsResponse',
  '2': [
    {'1': 'stickers', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineStickerInfo', '10': 'stickers'},
  ],
};

/// Descriptor for `EngineGetStickerSuggestionsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetStickerSuggestionsResponseDescriptor = $convert.base64Decode(
    'CiNFbmdpbmVHZXRTdGlja2VyU3VnZ2VzdGlvbnNSZXNwb25zZRI4CghzdGlja2VycxgBIAMoCz'
    'IcLnVuaWNsaWVudC5FbmdpbmVTdGlja2VySW5mb1IIc3RpY2tlcnM=');

@$core.Deprecated('Use engineSendCallRatingRequestDescriptor instead')
const EngineSendCallRatingRequest$json = {
  '1': 'EngineSendCallRatingRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'call_id', '3': 2, '4': 1, '5': 9, '10': 'callId'},
    {'1': 'rating', '3': 3, '4': 1, '5': 5, '10': 'rating'},
    {'1': 'comment', '3': 4, '4': 1, '5': 9, '10': 'comment'},
  ],
};

/// Descriptor for `EngineSendCallRatingRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSendCallRatingRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVTZW5kQ2FsbFJhdGluZ1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NhbGxfaWQYAiABKAlSBmNhbGxJZBIWCgZyYXRpbmcYAyABKAVSBnJhdGluZxIY'
    'Cgdjb21tZW50GAQgASgJUgdjb21tZW50');

@$core.Deprecated('Use engineFetchPeerStoriesRequestDescriptor instead')
const EngineFetchPeerStoriesRequest$json = {
  '1': 'EngineFetchPeerStoriesRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'peer_id', '3': 2, '4': 1, '5': 9, '10': 'peerId'},
  ],
};

/// Descriptor for `EngineFetchPeerStoriesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineFetchPeerStoriesRequestDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVGZXRjaFBlZXJTdG9yaWVzUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2'
    'NvdW50SWQSFwoHcGVlcl9pZBgCIAEoCVIGcGVlcklk');

@$core.Deprecated('Use engineFetchPeerStoriesResponseDescriptor instead')
const EngineFetchPeerStoriesResponse$json = {
  '1': 'EngineFetchPeerStoriesResponse',
  '2': [
    {'1': 'stories_json', '3': 1, '4': 1, '5': 9, '10': 'storiesJson'},
  ],
};

/// Descriptor for `EngineFetchPeerStoriesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineFetchPeerStoriesResponseDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVGZXRjaFBlZXJTdG9yaWVzUmVzcG9uc2USIQoMc3Rvcmllc19qc29uGAEgASgJUg'
    'tzdG9yaWVzSnNvbg==');

@$core.Deprecated('Use engineGetStoryAlbumsRequestDescriptor instead')
const EngineGetStoryAlbumsRequest$json = {
  '1': 'EngineGetStoryAlbumsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
  ],
};

/// Descriptor for `EngineGetStoryAlbumsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetStoryAlbumsRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVHZXRTdG9yeUFsYnVtc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElk');

@$core.Deprecated('Use engineStoryAlbumDescriptor instead')
const EngineStoryAlbum$json = {
  '1': 'EngineStoryAlbum',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 3, '10': 'id'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
    {'1': 'count', '3': 3, '4': 1, '5': 5, '10': 'count'},
  ],
};

/// Descriptor for `EngineStoryAlbum`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineStoryAlbumDescriptor = $convert.base64Decode(
    'ChBFbmdpbmVTdG9yeUFsYnVtEg4KAmlkGAEgASgDUgJpZBIUCgV0aXRsZRgCIAEoCVIFdGl0bG'
    'USFAoFY291bnQYAyABKAVSBWNvdW50');

@$core.Deprecated('Use engineGetStoryAlbumsResponseDescriptor instead')
const EngineGetStoryAlbumsResponse$json = {
  '1': 'EngineGetStoryAlbumsResponse',
  '2': [
    {'1': 'albums', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineStoryAlbum', '10': 'albums'},
  ],
};

/// Descriptor for `EngineGetStoryAlbumsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetStoryAlbumsResponseDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVHZXRTdG9yeUFsYnVtc1Jlc3BvbnNlEjMKBmFsYnVtcxgBIAMoCzIbLnVuaWNsaW'
    'VudC5FbmdpbmVTdG9yeUFsYnVtUgZhbGJ1bXM=');

@$core.Deprecated('Use engineGetAlbumStoriesRequestDescriptor instead')
const EngineGetAlbumStoriesRequest$json = {
  '1': 'EngineGetAlbumStoriesRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'album_id', '3': 2, '4': 1, '5': 3, '10': 'albumId'},
    {'1': 'offset', '3': 3, '4': 1, '5': 5, '10': 'offset'},
    {'1': 'limit', '3': 4, '4': 1, '5': 5, '10': 'limit'},
  ],
};

/// Descriptor for `EngineGetAlbumStoriesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetAlbumStoriesRequestDescriptor = $convert.base64Decode(
    'ChxFbmdpbmVHZXRBbGJ1bVN0b3JpZXNSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCWFjY2'
    '91bnRJZBIZCghhbGJ1bV9pZBgCIAEoA1IHYWxidW1JZBIWCgZvZmZzZXQYAyABKAVSBm9mZnNl'
    'dBIUCgVsaW1pdBgEIAEoBVIFbGltaXQ=');

@$core.Deprecated('Use engineGetAlbumStoriesResponseDescriptor instead')
const EngineGetAlbumStoriesResponse$json = {
  '1': 'EngineGetAlbumStoriesResponse',
  '2': [
    {'1': 'stories_json', '3': 1, '4': 1, '5': 9, '10': 'storiesJson'},
    {'1': 'total_count', '3': 2, '4': 1, '5': 5, '10': 'totalCount'},
  ],
};

/// Descriptor for `EngineGetAlbumStoriesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetAlbumStoriesResponseDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVHZXRBbGJ1bVN0b3JpZXNSZXNwb25zZRIhCgxzdG9yaWVzX2pzb24YASABKAlSC3'
    'N0b3JpZXNKc29uEh8KC3RvdGFsX2NvdW50GAIgASgFUgp0b3RhbENvdW50');

@$core.Deprecated('Use engineCreateStoryAlbumRequestDescriptor instead')
const EngineCreateStoryAlbumRequest$json = {
  '1': 'EngineCreateStoryAlbumRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
  ],
};

/// Descriptor for `EngineCreateStoryAlbumRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCreateStoryAlbumRequestDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVDcmVhdGVTdG9yeUFsYnVtUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2'
    'NvdW50SWQSFAoFdGl0bGUYAiABKAlSBXRpdGxl');

@$core.Deprecated('Use engineCreateStoryAlbumResponseDescriptor instead')
const EngineCreateStoryAlbumResponse$json = {
  '1': 'EngineCreateStoryAlbumResponse',
  '2': [
    {'1': 'album_id', '3': 1, '4': 1, '5': 3, '10': 'albumId'},
    {'1': 'title', '3': 2, '4': 1, '5': 9, '10': 'title'},
  ],
};

/// Descriptor for `EngineCreateStoryAlbumResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCreateStoryAlbumResponseDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVDcmVhdGVTdG9yeUFsYnVtUmVzcG9uc2USGQoIYWxidW1faWQYASABKANSB2FsYn'
    'VtSWQSFAoFdGl0bGUYAiABKAlSBXRpdGxl');

@$core.Deprecated('Use engineReorderStoryAlbumsRequestDescriptor instead')
const EngineReorderStoryAlbumsRequest$json = {
  '1': 'EngineReorderStoryAlbumsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'album_ids', '3': 2, '4': 3, '5': 3, '10': 'albumIds'},
  ],
};

/// Descriptor for `EngineReorderStoryAlbumsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineReorderStoryAlbumsRequestDescriptor = $convert.base64Decode(
    'Ch9FbmdpbmVSZW9yZGVyU3RvcnlBbGJ1bXNSZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKAlSCW'
    'FjY291bnRJZBIbCglhbGJ1bV9pZHMYAiADKANSCGFsYnVtSWRz');

@$core.Deprecated('Use engineGetCustomEmojiThumbsRequestDescriptor instead')
const EngineGetCustomEmojiThumbsRequest$json = {
  '1': 'EngineGetCustomEmojiThumbsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'document_ids', '3': 2, '4': 3, '5': 3, '10': 'documentIds'},
  ],
};

/// Descriptor for `EngineGetCustomEmojiThumbsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetCustomEmojiThumbsRequestDescriptor = $convert.base64Decode(
    'CiFFbmdpbmVHZXRDdXN0b21FbW9qaVRodW1ic1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCV'
    'IJYWNjb3VudElkEiEKDGRvY3VtZW50X2lkcxgCIAMoA1ILZG9jdW1lbnRJZHM=');

@$core.Deprecated('Use engineCustomEmojiThumbDescriptor instead')
const EngineCustomEmojiThumb$json = {
  '1': 'EngineCustomEmojiThumb',
  '2': [
    {'1': 'document_id', '3': 1, '4': 1, '5': 3, '10': 'documentId'},
    {'1': 'thumb_b64', '3': 2, '4': 1, '5': 9, '10': 'thumbB64'},
    {'1': 'path_b64', '3': 3, '4': 1, '5': 9, '10': 'pathB64'},
  ],
};

/// Descriptor for `EngineCustomEmojiThumb`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCustomEmojiThumbDescriptor = $convert.base64Decode(
    'ChZFbmdpbmVDdXN0b21FbW9qaVRodW1iEh8KC2RvY3VtZW50X2lkGAEgASgDUgpkb2N1bWVudE'
    'lkEhsKCXRodW1iX2I2NBgCIAEoCVIIdGh1bWJCNjQSGQoIcGF0aF9iNjQYAyABKAlSB3BhdGhC'
    'NjQ=');

@$core.Deprecated('Use engineGetCustomEmojiThumbsResponseDescriptor instead')
const EngineGetCustomEmojiThumbsResponse$json = {
  '1': 'EngineGetCustomEmojiThumbsResponse',
  '2': [
    {'1': 'thumbs', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineCustomEmojiThumb', '10': 'thumbs'},
  ],
};

/// Descriptor for `EngineGetCustomEmojiThumbsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetCustomEmojiThumbsResponseDescriptor = $convert.base64Decode(
    'CiJFbmdpbmVHZXRDdXN0b21FbW9qaVRodW1ic1Jlc3BvbnNlEjkKBnRodW1icxgBIAMoCzIhLn'
    'VuaWNsaWVudC5FbmdpbmVDdXN0b21FbW9qaVRodW1iUgZ0aHVtYnM=');

@$core.Deprecated('Use engineGetSavedSublistsRequestDescriptor instead')
const EngineGetSavedSublistsRequest$json = {
  '1': 'EngineGetSavedSublistsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'limit', '3': 2, '4': 1, '5': 5, '10': 'limit'},
    {'1': 'offset_date', '3': 3, '4': 1, '5': 5, '10': 'offsetDate'},
    {'1': 'offset_id', '3': 4, '4': 1, '5': 5, '10': 'offsetId'},
    {'1': 'exclude_pinned', '3': 5, '4': 1, '5': 8, '10': 'excludePinned'},
  ],
};

/// Descriptor for `EngineGetSavedSublistsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSavedSublistsRequestDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVHZXRTYXZlZFN1Ymxpc3RzUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2'
    'NvdW50SWQSFAoFbGltaXQYAiABKAVSBWxpbWl0Eh8KC29mZnNldF9kYXRlGAMgASgFUgpvZmZz'
    'ZXREYXRlEhsKCW9mZnNldF9pZBgEIAEoBVIIb2Zmc2V0SWQSJQoOZXhjbHVkZV9waW5uZWQYBS'
    'ABKAhSDWV4Y2x1ZGVQaW5uZWQ=');

@$core.Deprecated('Use engineSavedSublistDescriptor instead')
const EngineSavedSublist$json = {
  '1': 'EngineSavedSublist',
  '2': [
    {'1': 'peer_id', '3': 1, '4': 1, '5': 9, '10': 'peerId'},
    {'1': 'peer_name', '3': 2, '4': 1, '5': 9, '10': 'peerName'},
    {'1': 'avatar_path', '3': 3, '4': 1, '5': 9, '10': 'avatarPath'},
    {'1': 'type', '3': 4, '4': 1, '5': 5, '10': 'type'},
    {'1': 'is_pinned', '3': 5, '4': 1, '5': 8, '10': 'isPinned'},
    {'1': 'top_message', '3': 6, '4': 1, '5': 5, '10': 'topMessage'},
    {'1': 'last_msg_text', '3': 7, '4': 1, '5': 9, '10': 'lastMsgText'},
    {'1': 'last_msg_time', '3': 8, '4': 1, '5': 3, '10': 'lastMsgTime'},
    {'1': 'is_self', '3': 9, '4': 1, '5': 8, '10': 'isSelf'},
    {'1': 'unread_count', '3': 10, '4': 1, '5': 5, '10': 'unreadCount'},
  ],
};

/// Descriptor for `EngineSavedSublist`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSavedSublistDescriptor = $convert.base64Decode(
    'ChJFbmdpbmVTYXZlZFN1Ymxpc3QSFwoHcGVlcl9pZBgBIAEoCVIGcGVlcklkEhsKCXBlZXJfbm'
    'FtZRgCIAEoCVIIcGVlck5hbWUSHwoLYXZhdGFyX3BhdGgYAyABKAlSCmF2YXRhclBhdGgSEgoE'
    'dHlwZRgEIAEoBVIEdHlwZRIbCglpc19waW5uZWQYBSABKAhSCGlzUGlubmVkEh8KC3RvcF9tZX'
    'NzYWdlGAYgASgFUgp0b3BNZXNzYWdlEiIKDWxhc3RfbXNnX3RleHQYByABKAlSC2xhc3RNc2dU'
    'ZXh0EiIKDWxhc3RfbXNnX3RpbWUYCCABKANSC2xhc3RNc2dUaW1lEhcKB2lzX3NlbGYYCSABKA'
    'hSBmlzU2VsZhIhCgx1bnJlYWRfY291bnQYCiABKAVSC3VucmVhZENvdW50');

@$core.Deprecated('Use engineGetSavedSublistsResponseDescriptor instead')
const EngineGetSavedSublistsResponse$json = {
  '1': 'EngineGetSavedSublistsResponse',
  '2': [
    {'1': 'sublists', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineSavedSublist', '10': 'sublists'},
    {'1': 'total_count', '3': 2, '4': 1, '5': 5, '10': 'totalCount'},
  ],
};

/// Descriptor for `EngineGetSavedSublistsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSavedSublistsResponseDescriptor = $convert.base64Decode(
    'Ch5FbmdpbmVHZXRTYXZlZFN1Ymxpc3RzUmVzcG9uc2USOQoIc3VibGlzdHMYASADKAsyHS51bm'
    'ljbGllbnQuRW5naW5lU2F2ZWRTdWJsaXN0UghzdWJsaXN0cxIfCgt0b3RhbF9jb3VudBgCIAEo'
    'BVIKdG90YWxDb3VudA==');

@$core.Deprecated('Use engineGetSavedReactionTagsRequestDescriptor instead')
const EngineGetSavedReactionTagsRequest$json = {
  '1': 'EngineGetSavedReactionTagsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'sublist_peer_id', '3': 2, '4': 1, '5': 9, '10': 'sublistPeerId'},
  ],
};

/// Descriptor for `EngineGetSavedReactionTagsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSavedReactionTagsRequestDescriptor = $convert.base64Decode(
    'CiFFbmdpbmVHZXRTYXZlZFJlYWN0aW9uVGFnc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCV'
    'IJYWNjb3VudElkEiYKD3N1Ymxpc3RfcGVlcl9pZBgCIAEoCVINc3VibGlzdFBlZXJJZA==');

@$core.Deprecated('Use engineSavedReactionTagDescriptor instead')
const EngineSavedReactionTag$json = {
  '1': 'EngineSavedReactionTag',
  '2': [
    {'1': 'emoji', '3': 1, '4': 1, '5': 9, '10': 'emoji'},
    {'1': 'custom_id', '3': 2, '4': 1, '5': 3, '10': 'customId'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {'1': 'count', '3': 4, '4': 1, '5': 5, '10': 'count'},
  ],
};

/// Descriptor for `EngineSavedReactionTag`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSavedReactionTagDescriptor = $convert.base64Decode(
    'ChZFbmdpbmVTYXZlZFJlYWN0aW9uVGFnEhQKBWVtb2ppGAEgASgJUgVlbW9qaRIbCgljdXN0b2'
    '1faWQYAiABKANSCGN1c3RvbUlkEhQKBXRpdGxlGAMgASgJUgV0aXRsZRIUCgVjb3VudBgEIAEo'
    'BVIFY291bnQ=');

@$core.Deprecated('Use engineGetSavedReactionTagsResponseDescriptor instead')
const EngineGetSavedReactionTagsResponse$json = {
  '1': 'EngineGetSavedReactionTagsResponse',
  '2': [
    {'1': 'tags', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineSavedReactionTag', '10': 'tags'},
  ],
};

/// Descriptor for `EngineGetSavedReactionTagsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetSavedReactionTagsResponseDescriptor = $convert.base64Decode(
    'CiJFbmdpbmVHZXRTYXZlZFJlYWN0aW9uVGFnc1Jlc3BvbnNlEjUKBHRhZ3MYASADKAsyIS51bm'
    'ljbGllbnQuRW5naW5lU2F2ZWRSZWFjdGlvblRhZ1IEdGFncw==');

@$core.Deprecated('Use engineRenameSavedReactionTagRequestDescriptor instead')
const EngineRenameSavedReactionTagRequest$json = {
  '1': 'EngineRenameSavedReactionTagRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'emoji', '3': 2, '4': 1, '5': 9, '10': 'emoji'},
    {'1': 'custom_id', '3': 3, '4': 1, '5': 3, '10': 'customId'},
    {'1': 'title', '3': 4, '4': 1, '5': 9, '10': 'title'},
  ],
};

/// Descriptor for `EngineRenameSavedReactionTagRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineRenameSavedReactionTagRequestDescriptor = $convert.base64Decode(
    'CiNFbmdpbmVSZW5hbWVTYXZlZFJlYWN0aW9uVGFnUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgAS'
    'gJUglhY2NvdW50SWQSFAoFZW1vamkYAiABKAlSBWVtb2ppEhsKCWN1c3RvbV9pZBgDIAEoA1II'
    'Y3VzdG9tSWQSFAoFdGl0bGUYBCABKAlSBXRpdGxl');

@$core.Deprecated('Use engineClearCallHistoryRequestDescriptor instead')
const EngineClearCallHistoryRequest$json = {
  '1': 'EngineClearCallHistoryRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'revoke', '3': 2, '4': 1, '5': 8, '10': 'revoke'},
  ],
};

/// Descriptor for `EngineClearCallHistoryRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineClearCallHistoryRequestDescriptor = $convert.base64Decode(
    'Ch1FbmdpbmVDbGVhckNhbGxIaXN0b3J5UmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2'
    'NvdW50SWQSFgoGcmV2b2tlGAIgASgIUgZyZXZva2U=');

@$core.Deprecated('Use engineGetCustomEmojiFilesRequestDescriptor instead')
const EngineGetCustomEmojiFilesRequest$json = {
  '1': 'EngineGetCustomEmojiFilesRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'document_ids', '3': 2, '4': 3, '5': 3, '10': 'documentIds'},
  ],
};

/// Descriptor for `EngineGetCustomEmojiFilesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetCustomEmojiFilesRequestDescriptor = $convert.base64Decode(
    'CiBFbmdpbmVHZXRDdXN0b21FbW9qaUZpbGVzUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUg'
    'lhY2NvdW50SWQSIQoMZG9jdW1lbnRfaWRzGAIgAygDUgtkb2N1bWVudElkcw==');

@$core.Deprecated('Use engineCustomEmojiFileDescriptor instead')
const EngineCustomEmojiFile$json = {
  '1': 'EngineCustomEmojiFile',
  '2': [
    {'1': 'document_id', '3': 1, '4': 1, '5': 3, '10': 'documentId'},
    {'1': 'mime_type', '3': 2, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'file_data', '3': 3, '4': 1, '5': 12, '10': 'fileData'},
  ],
};

/// Descriptor for `EngineCustomEmojiFile`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCustomEmojiFileDescriptor = $convert.base64Decode(
    'ChVFbmdpbmVDdXN0b21FbW9qaUZpbGUSHwoLZG9jdW1lbnRfaWQYASABKANSCmRvY3VtZW50SW'
    'QSGwoJbWltZV90eXBlGAIgASgJUghtaW1lVHlwZRIbCglmaWxlX2RhdGEYAyABKAxSCGZpbGVE'
    'YXRh');

@$core.Deprecated('Use engineGetCustomEmojiFilesResponseDescriptor instead')
const EngineGetCustomEmojiFilesResponse$json = {
  '1': 'EngineGetCustomEmojiFilesResponse',
  '2': [
    {'1': 'files', '3': 1, '4': 3, '5': 11, '6': '.uniclient.EngineCustomEmojiFile', '10': 'files'},
  ],
};

/// Descriptor for `EngineGetCustomEmojiFilesResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetCustomEmojiFilesResponseDescriptor = $convert.base64Decode(
    'CiFFbmdpbmVHZXRDdXN0b21FbW9qaUZpbGVzUmVzcG9uc2USNgoFZmlsZXMYASADKAsyIC51bm'
    'ljbGllbnQuRW5naW5lQ3VzdG9tRW1vamlGaWxlUgVmaWxlcw==');

@$core.Deprecated('Use engineGetCustomEmojiSetInfoRequestDescriptor instead')
const EngineGetCustomEmojiSetInfoRequest$json = {
  '1': 'EngineGetCustomEmojiSetInfoRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'document_id', '3': 2, '4': 1, '5': 3, '10': 'documentId'},
  ],
};

/// Descriptor for `EngineGetCustomEmojiSetInfoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetCustomEmojiSetInfoRequestDescriptor = $convert.base64Decode(
    'CiJFbmdpbmVHZXRDdXN0b21FbW9qaVNldEluZm9SZXF1ZXN0Eh0KCmFjY291bnRfaWQYASABKA'
    'lSCWFjY291bnRJZBIfCgtkb2N1bWVudF9pZBgCIAEoA1IKZG9jdW1lbnRJZA==');

@$core.Deprecated('Use engineGetCustomEmojiSetInfoResponseDescriptor instead')
const EngineGetCustomEmojiSetInfoResponse$json = {
  '1': 'EngineGetCustomEmojiSetInfoResponse',
  '2': [
    {'1': 'set_id', '3': 1, '4': 1, '5': 3, '10': 'setId'},
    {'1': 'access_hash', '3': 2, '4': 1, '5': 3, '10': 'accessHash'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {'1': 'short_name', '3': 4, '4': 1, '5': 9, '10': 'shortName'},
    {'1': 'count', '3': 5, '4': 1, '5': 5, '10': 'count'},
    {'1': 'found', '3': 6, '4': 1, '5': 8, '10': 'found'},
  ],
};

/// Descriptor for `EngineGetCustomEmojiSetInfoResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetCustomEmojiSetInfoResponseDescriptor = $convert.base64Decode(
    'CiNFbmdpbmVHZXRDdXN0b21FbW9qaVNldEluZm9SZXNwb25zZRIVCgZzZXRfaWQYASABKANSBX'
    'NldElkEh8KC2FjY2Vzc19oYXNoGAIgASgDUgphY2Nlc3NIYXNoEhQKBXRpdGxlGAMgASgJUgV0'
    'aXRsZRIdCgpzaG9ydF9uYW1lGAQgASgJUglzaG9ydE5hbWUSFAoFY291bnQYBSABKAVSBWNvdW'
    '50EhQKBWZvdW5kGAYgASgIUgVmb3VuZA==');

@$core.Deprecated('Use engineSetUserNoForwardsFlagsRequestDescriptor instead')
const EngineSetUserNoForwardsFlagsRequest$json = {
  '1': 'EngineSetUserNoForwardsFlagsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'user_id', '3': 2, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'my_enabled', '3': 3, '4': 1, '5': 8, '10': 'myEnabled'},
    {'1': 'peer_enabled', '3': 4, '4': 1, '5': 8, '10': 'peerEnabled'},
  ],
};

/// Descriptor for `EngineSetUserNoForwardsFlagsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSetUserNoForwardsFlagsRequestDescriptor = $convert.base64Decode(
    'CiNFbmdpbmVTZXRVc2VyTm9Gb3J3YXJkc0ZsYWdzUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgAS'
    'gJUglhY2NvdW50SWQSFwoHdXNlcl9pZBgCIAEoCVIGdXNlcklkEh0KCm15X2VuYWJsZWQYAyAB'
    'KAhSCW15RW5hYmxlZBIhCgxwZWVyX2VuYWJsZWQYBCABKAhSC3BlZXJFbmFibGVk');

@$core.Deprecated('Use engineReorderPinnedDialogsRequestDescriptor instead')
const EngineReorderPinnedDialogsRequest$json = {
  '1': 'EngineReorderPinnedDialogsRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_ids', '3': 2, '4': 3, '5': 9, '10': 'chatIds'},
  ],
};

/// Descriptor for `EngineReorderPinnedDialogsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineReorderPinnedDialogsRequestDescriptor = $convert.base64Decode(
    'CiFFbmdpbmVSZW9yZGVyUGlubmVkRGlhbG9nc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCV'
    'IJYWNjb3VudElkEhkKCGNoYXRfaWRzGAIgAygJUgdjaGF0SWRz');

@$core.Deprecated('Use engineReorderDialogFiltersRequestDescriptor instead')
const EngineReorderDialogFiltersRequest$json = {
  '1': 'EngineReorderDialogFiltersRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'filter_ids', '3': 2, '4': 3, '5': 5, '10': 'filterIds'},
  ],
};

/// Descriptor for `EngineReorderDialogFiltersRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineReorderDialogFiltersRequestDescriptor = $convert.base64Decode(
    'CiFFbmdpbmVSZW9yZGVyRGlhbG9nRmlsdGVyc1JlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCV'
    'IJYWNjb3VudElkEh0KCmZpbHRlcl9pZHMYAiADKAVSCWZpbHRlcklkcw==');

@$core.Deprecated('Use engineGetForumTopicsWithOffsetRequestDescriptor instead')
const EngineGetForumTopicsWithOffsetRequest$json = {
  '1': 'EngineGetForumTopicsWithOffsetRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'offset_date', '3': 3, '4': 1, '5': 5, '10': 'offsetDate'},
    {'1': 'offset_id', '3': 4, '4': 1, '5': 5, '10': 'offsetId'},
    {'1': 'offset_topic', '3': 5, '4': 1, '5': 5, '10': 'offsetTopic'},
  ],
};

/// Descriptor for `EngineGetForumTopicsWithOffsetRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineGetForumTopicsWithOffsetRequestDescriptor = $convert.base64Decode(
    'CiVFbmdpbmVHZXRGb3J1bVRvcGljc1dpdGhPZmZzZXRSZXF1ZXN0Eh0KCmFjY291bnRfaWQYAS'
    'ABKAlSCWFjY291bnRJZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSHwoLb2Zmc2V0X2RhdGUY'
    'AyABKAVSCm9mZnNldERhdGUSGwoJb2Zmc2V0X2lkGAQgASgFUghvZmZzZXRJZBIhCgxvZmZzZX'
    'RfdG9waWMYBSABKAVSC29mZnNldFRvcGlj');


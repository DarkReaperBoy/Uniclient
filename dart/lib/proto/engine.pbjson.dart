//
//  Generated code. Do not modify.
//  source: engine.proto
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
  ],
};

/// Descriptor for `AccountInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List accountInfoDescriptor = $convert.base64Decode(
    'CgtBY2NvdW50SW5mbxIOCgJpZBgBIAEoCVICaWQSGgoIcGxhdGZvcm0YAiABKAlSCHBsYXRmb3'
    'JtEiEKDGRpc3BsYXlfbmFtZRgDIAEoCVILZGlzcGxheU5hbWUSHwoLYXZhdGFyX3BhdGgYBCAB'
    'KAlSCmF2YXRhclBhdGgSHQoKc29ydF9vcmRlchgFIAEoBVIJc29ydE9yZGVyEh0KCmNvbm5fc3'
    'RhdGUYBiABKAVSCWNvbm5TdGF0ZQ==');

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
    {'1': 'unread_count', '3': 10, '4': 1, '5': 5, '10': 'unreadCount'},
    {'1': 'is_muted', '3': 11, '4': 1, '5': 8, '10': 'isMuted'},
    {'1': 'is_pinned', '3': 12, '4': 1, '5': 8, '10': 'isPinned'},
    {'1': 'is_archived', '3': 13, '4': 1, '5': 8, '10': 'isArchived'},
    {'1': 'draft_text', '3': 14, '4': 1, '5': 9, '10': 'draftText'},
    {'1': 'member_count', '3': 15, '4': 1, '5': 5, '10': 'memberCount'},
    {'1': 'parent_id', '3': 16, '4': 1, '5': 9, '10': 'parentId'},
  ],
};

/// Descriptor for `EngineChatInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineChatInfoDescriptor = $convert.base64Decode(
    'Cg5FbmdpbmVDaGF0SW5mbxIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SWQSFwoHY2hhdF'
    '9pZBgCIAEoCVIGY2hhdElkEhIKBHR5cGUYAyABKAVSBHR5cGUSFAoFdGl0bGUYBCABKAlSBXRp'
    'dGxlEh8KC2F2YXRhcl9wYXRoGAUgASgJUgphdmF0YXJQYXRoEh4KC2xhc3RfbXNnX2lkGAYgAS'
    'gJUglsYXN0TXNnSWQSIgoNbGFzdF9tc2dfdGV4dBgHIAEoCVILbGFzdE1zZ1RleHQSIgoNbGFz'
    'dF9tc2dfdGltZRgIIAEoA1ILbGFzdE1zZ1RpbWUSJgoPbGFzdF9tc2dfc2VuZGVyGAkgASgJUg'
    '1sYXN0TXNnU2VuZGVyEiEKDHVucmVhZF9jb3VudBgKIAEoBVILdW5yZWFkQ291bnQSGQoIaXNf'
    'bXV0ZWQYCyABKAhSB2lzTXV0ZWQSGwoJaXNfcGlubmVkGAwgASgIUghpc1Bpbm5lZBIfCgtpc1'
    '9hcmNoaXZlZBgNIAEoCFIKaXNBcmNoaXZlZBIdCgpkcmFmdF90ZXh0GA4gASgJUglkcmFmdFRl'
    'eHQSIQoMbWVtYmVyX2NvdW50GA8gASgFUgttZW1iZXJDb3VudBIbCglwYXJlbnRfaWQYECABKA'
    'lSCHBhcmVudElk');

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
  ],
};

/// Descriptor for `EngineMuteChatRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineMuteChatRequestDescriptor = $convert.base64Decode(
    'ChVFbmdpbmVNdXRlQ2hhdFJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudElkEh'
    'cKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIUCgVtdXRlZBgDIAEoCFIFbXV0ZWQ=');

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
    'b3dubG9hZF9zdGF0ZRgbIAEoBVISbWVkaWFEb3dubG9hZFN0YXRl');

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
  ],
};

/// Descriptor for `EngineSendMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSendMessageRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVTZW5kTWVzc2FnZVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBISCgR0ZXh0GAMgASgJUgR0ZXh0Eh4KC3JlcGx5'
    'X3RvX2lkGAQgASgJUglyZXBseVRvSWQ=');

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
  ],
};

/// Descriptor for `EngineEditMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineEditMessageRequestDescriptor = $convert.base64Decode(
    'ChhFbmdpbmVFZGl0TWVzc2FnZVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3VudE'
    'lkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lkEhkKCG5l'
    'd190ZXh0GAQgASgJUgduZXdUZXh0');

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

@$core.Deprecated('Use engineForwardMessageRequestDescriptor instead')
const EngineForwardMessageRequest$json = {
  '1': 'EngineForwardMessageRequest',
  '2': [
    {'1': 'account_id', '3': 1, '4': 1, '5': 9, '10': 'accountId'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'msg_id', '3': 3, '4': 1, '5': 9, '10': 'msgId'},
    {'1': 'to_chat_id', '3': 4, '4': 1, '5': 9, '10': 'toChatId'},
  ],
};

/// Descriptor for `EngineForwardMessageRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineForwardMessageRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVGb3J3YXJkTWVzc2FnZVJlcXVlc3QSHQoKYWNjb3VudF9pZBgBIAEoCVIJYWNjb3'
    'VudElkEhcKB2NoYXRfaWQYAiABKAlSBmNoYXRJZBIVCgZtc2dfaWQYAyABKAlSBW1zZ0lkEhwK'
    'CnRvX2NoYXRfaWQYBCABKAlSCHRvQ2hhdElk');

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
  ],
};

/// Descriptor for `EngineUploadFileRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineUploadFileRequestDescriptor = $convert.base64Decode(
    'ChdFbmdpbmVVcGxvYWRGaWxlUmVxdWVzdBIdCgphY2NvdW50X2lkGAEgASgJUglhY2NvdW50SW'
    'QSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEhsKCWZpbGVfcGF0aBgDIAEoCVIIZmlsZVBhdGgS'
    'GAoHY2FwdGlvbhgEIAEoCVIHY2FwdGlvbg==');

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
  ],
};

/// Descriptor for `EngineSearchMessagesRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSearchMessagesRequestDescriptor = $convert.base64Decode(
    'ChtFbmdpbmVTZWFyY2hNZXNzYWdlc1JlcXVlc3QSFAoFcXVlcnkYASABKAlSBXF1ZXJ5Eh0KCm'
    'FjY291bnRfaWQYAiABKAlSCWFjY291bnRJZBIUCgVsaW1pdBgDIAEoBVIFbGltaXQ=');

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
    'EoCFISbm90aWZ5TWVudGlvbnNPbmx5');

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
    'ChhoYXNfbm90aWZ5X21lbnRpb25zX29ubHkYDyABKAhSFWhhc05vdGlmeU1lbnRpb25zT25seQ'
    '==');


//
//  Generated code. Do not modify.
//  source: models.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use chatTypeDescriptor instead')
const ChatType$json = {
  '1': 'ChatType',
  '2': [
    {'1': 'CHAT_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'CHAT_TYPE_DM', '2': 1},
    {'1': 'CHAT_TYPE_GROUP', '2': 2},
    {'1': 'CHAT_TYPE_CHANNEL', '2': 3},
    {'1': 'CHAT_TYPE_TOPIC', '2': 4},
  ],
};

/// Descriptor for `ChatType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List chatTypeDescriptor = $convert.base64Decode(
    'CghDaGF0VHlwZRIZChVDSEFUX1RZUEVfVU5TUEVDSUZJRUQQABIQCgxDSEFUX1RZUEVfRE0QAR'
    'ITCg9DSEFUX1RZUEVfR1JPVVAQAhIVChFDSEFUX1RZUEVfQ0hBTk5FTBADEhMKD0NIQVRfVFlQ'
    'RV9UT1BJQxAE');

@$core.Deprecated('Use messageStatusDescriptor instead')
const MessageStatus$json = {
  '1': 'MessageStatus',
  '2': [
    {'1': 'MESSAGE_STATUS_UNSPECIFIED', '2': 0},
    {'1': 'MESSAGE_STATUS_SENDING', '2': 1},
    {'1': 'MESSAGE_STATUS_SENT', '2': 2},
    {'1': 'MESSAGE_STATUS_DELIVERED', '2': 3},
    {'1': 'MESSAGE_STATUS_READ', '2': 4},
    {'1': 'MESSAGE_STATUS_FAILED', '2': 5},
  ],
};

/// Descriptor for `MessageStatus`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List messageStatusDescriptor = $convert.base64Decode(
    'Cg1NZXNzYWdlU3RhdHVzEh4KGk1FU1NBR0VfU1RBVFVTX1VOU1BFQ0lGSUVEEAASGgoWTUVTU0'
    'FHRV9TVEFUVVNfU0VORElORxABEhcKE01FU1NBR0VfU1RBVFVTX1NFTlQQAhIcChhNRVNTQUdF'
    'X1NUQVRVU19ERUxJVkVSRUQQAxIXChNNRVNTQUdFX1NUQVRVU19SRUFEEAQSGQoVTUVTU0FHRV'
    '9TVEFUVVNfRkFJTEVEEAU=');

@$core.Deprecated('Use updateTypeDescriptor instead')
const UpdateType$json = {
  '1': 'UpdateType',
  '2': [
    {'1': 'UPDATE_TYPE_UNSPECIFIED', '2': 0},
    {'1': 'UPDATE_TYPE_NEW_MESSAGE', '2': 1},
    {'1': 'UPDATE_TYPE_EDIT_MESSAGE', '2': 2},
    {'1': 'UPDATE_TYPE_DELETE_MESSAGE', '2': 3},
    {'1': 'UPDATE_TYPE_READ_STATE', '2': 4},
    {'1': 'UPDATE_TYPE_USER_STATUS', '2': 5},
    {'1': 'UPDATE_TYPE_TYPING', '2': 6},
    {'1': 'UPDATE_TYPE_CALL_STATE', '2': 7},
    {'1': 'UPDATE_TYPE_GROUP_MEMBERS', '2': 8},
    {'1': 'UPDATE_TYPE_VERIFICATION', '2': 9},
    {'1': 'UPDATE_TYPE_CONNECTIVITY', '2': 10},
  ],
};

/// Descriptor for `UpdateType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List updateTypeDescriptor = $convert.base64Decode(
    'CgpVcGRhdGVUeXBlEhsKF1VQREFURV9UWVBFX1VOU1BFQ0lGSUVEEAASGwoXVVBEQVRFX1RZUE'
    'VfTkVXX01FU1NBR0UQARIcChhVUERBVEVfVFlQRV9FRElUX01FU1NBR0UQAhIeChpVUERBVEVf'
    'VFlQRV9ERUxFVEVfTUVTU0FHRRADEhoKFlVQREFURV9UWVBFX1JFQURfU1RBVEUQBBIbChdVUE'
    'RBVEVfVFlQRV9VU0VSX1NUQVRVUxAFEhYKElVQREFURV9UWVBFX1RZUElORxAGEhoKFlVQREFU'
    'RV9UWVBFX0NBTExfU1RBVEUQBxIdChlVUERBVEVfVFlQRV9HUk9VUF9NRU1CRVJTEAgSHAoYVV'
    'BEQVRFX1RZUEVfVkVSSUZJQ0FUSU9OEAkSHAoYVVBEQVRFX1RZUEVfQ09OTkVDVElWSVRZEAo=');

@$core.Deprecated('Use callStateDescriptor instead')
const CallState$json = {
  '1': 'CallState',
  '2': [
    {'1': 'CALL_STATE_UNSPECIFIED', '2': 0},
    {'1': 'CALL_STATE_RINGING', '2': 1},
    {'1': 'CALL_STATE_CONNECTING', '2': 2},
    {'1': 'CALL_STATE_ACTIVE', '2': 3},
    {'1': 'CALL_STATE_ENDED', '2': 4},
  ],
};

/// Descriptor for `CallState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List callStateDescriptor = $convert.base64Decode(
    'CglDYWxsU3RhdGUSGgoWQ0FMTF9TVEFURV9VTlNQRUNJRklFRBAAEhYKEkNBTExfU1RBVEVfUk'
    'lOR0lORxABEhkKFUNBTExfU1RBVEVfQ09OTkVDVElORxACEhUKEUNBTExfU1RBVEVfQUNUSVZF'
    'EAMSFAoQQ0FMTF9TVEFURV9FTkRFRBAE');

@$core.Deprecated('Use authModeDescriptor instead')
const AuthMode$json = {
  '1': 'AuthMode',
  '2': [
    {'1': 'AUTH_MODE_UNSPECIFIED', '2': 0},
    {'1': 'AUTH_MODE_BOT', '2': 1},
    {'1': 'AUTH_MODE_USER', '2': 2},
  ],
};

/// Descriptor for `AuthMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List authModeDescriptor = $convert.base64Decode(
    'CghBdXRoTW9kZRIZChVBVVRIX01PREVfVU5TUEVDSUZJRUQQABIRCg1BVVRIX01PREVfQk9UEA'
    'ESEgoOQVVUSF9NT0RFX1VTRVIQAg==');

@$core.Deprecated('Use authConfigDescriptor instead')
const AuthConfig$json = {
  '1': 'AuthConfig',
  '2': [
    {'1': 'mode', '3': 1, '4': 1, '5': 14, '6': '.uniclient.AuthMode', '10': 'mode'},
    {'1': 'bot_token', '3': 2, '4': 1, '5': 9, '10': 'botToken'},
    {'1': 'phone', '3': 3, '4': 1, '5': 9, '10': 'phone'},
    {'1': 'otp', '3': 4, '4': 1, '5': 9, '10': 'otp'},
    {'1': 'password_2f', '3': 5, '4': 1, '5': 9, '10': 'password2f'},
    {'1': 'extra', '3': 6, '4': 3, '5': 11, '6': '.uniclient.AuthConfig.ExtraEntry', '10': 'extra'},
  ],
  '3': [AuthConfig_ExtraEntry$json],
};

@$core.Deprecated('Use authConfigDescriptor instead')
const AuthConfig_ExtraEntry$json = {
  '1': 'ExtraEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `AuthConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List authConfigDescriptor = $convert.base64Decode(
    'CgpBdXRoQ29uZmlnEicKBG1vZGUYASABKA4yEy51bmljbGllbnQuQXV0aE1vZGVSBG1vZGUSGw'
    'oJYm90X3Rva2VuGAIgASgJUghib3RUb2tlbhIUCgVwaG9uZRgDIAEoCVIFcGhvbmUSEAoDb3Rw'
    'GAQgASgJUgNvdHASHwoLcGFzc3dvcmRfMmYYBSABKAlSCnBhc3N3b3JkMmYSNgoFZXh0cmEYBi'
    'ADKAsyIC51bmljbGllbnQuQXV0aENvbmZpZy5FeHRyYUVudHJ5UgVleHRyYRo4CgpFeHRyYUVu'
    'dHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBXZhbHVlGAIgASgJUgV2YWx1ZToCOAE=');

@$core.Deprecated('Use paginationOptsDescriptor instead')
const PaginationOpts$json = {
  '1': 'PaginationOpts',
  '2': [
    {'1': 'limit', '3': 1, '4': 1, '5': 5, '10': 'limit'},
    {'1': 'offset', '3': 2, '4': 1, '5': 9, '10': 'offset'},
  ],
};

/// Descriptor for `PaginationOpts`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List paginationOptsDescriptor = $convert.base64Decode(
    'Cg5QYWdpbmF0aW9uT3B0cxIUCgVsaW1pdBgBIAEoBVIFbGltaXQSFgoGb2Zmc2V0GAIgASgJUg'
    'ZvZmZzZXQ=');

@$core.Deprecated('Use userDescriptor instead')
const User$json = {
  '1': 'User',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'username', '3': 2, '4': 1, '5': 9, '10': 'username'},
    {'1': 'display_name', '3': 3, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'phone', '3': 4, '4': 1, '5': 9, '10': 'phone'},
    {'1': 'avatar_url', '3': 5, '4': 1, '5': 9, '10': 'avatarUrl'},
    {'1': 'avatar_b64', '3': 6, '4': 1, '5': 9, '10': 'avatarB64'},
    {'1': 'is_bot', '3': 7, '4': 1, '5': 8, '10': 'isBot'},
    {'1': 'is_online', '3': 8, '4': 1, '5': 8, '10': 'isOnline'},
    {'1': 'last_seen_ms', '3': 9, '4': 1, '5': 3, '10': 'lastSeenMs'},
    {'1': 'platform', '3': 10, '4': 1, '5': 9, '10': 'platform'},
  ],
};

/// Descriptor for `User`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userDescriptor = $convert.base64Decode(
    'CgRVc2VyEg4KAmlkGAEgASgJUgJpZBIaCgh1c2VybmFtZRgCIAEoCVIIdXNlcm5hbWUSIQoMZG'
    'lzcGxheV9uYW1lGAMgASgJUgtkaXNwbGF5TmFtZRIUCgVwaG9uZRgEIAEoCVIFcGhvbmUSHQoK'
    'YXZhdGFyX3VybBgFIAEoCVIJYXZhdGFyVXJsEh0KCmF2YXRhcl9iNjQYBiABKAlSCWF2YXRhck'
    'I2NBIVCgZpc19ib3QYByABKAhSBWlzQm90EhsKCWlzX29ubGluZRgIIAEoCFIIaXNPbmxpbmUS'
    'IAoMbGFzdF9zZWVuX21zGAkgASgDUgpsYXN0U2Vlbk1zEhoKCHBsYXRmb3JtGAogASgJUghwbG'
    'F0Zm9ybQ==');

@$core.Deprecated('Use dialogDescriptor instead')
const Dialog$json = {
  '1': 'Dialog',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'type', '3': 2, '4': 1, '5': 14, '6': '.uniclient.ChatType', '10': 'type'},
    {'1': 'title', '3': 3, '4': 1, '5': 9, '10': 'title'},
    {'1': 'avatar_url', '3': 4, '4': 1, '5': 9, '10': 'avatarUrl'},
    {'1': 'avatar_b64', '3': 5, '4': 1, '5': 9, '10': 'avatarB64'},
    {'1': 'last_message', '3': 6, '4': 1, '5': 11, '6': '.uniclient.Message', '10': 'lastMessage'},
    {'1': 'unread_count', '3': 7, '4': 1, '5': 5, '10': 'unreadCount'},
    {'1': 'is_muted', '3': 8, '4': 1, '5': 8, '10': 'isMuted'},
    {'1': 'is_pinned', '3': 9, '4': 1, '5': 8, '10': 'isPinned'},
    {'1': 'is_archived', '3': 10, '4': 1, '5': 8, '10': 'isArchived'},
    {'1': 'member_count', '3': 11, '4': 1, '5': 5, '10': 'memberCount'},
    {'1': 'parent_id', '3': 12, '4': 1, '5': 9, '10': 'parentId'},
    {'1': 'platform', '3': 13, '4': 1, '5': 9, '10': 'platform'},
  ],
};

/// Descriptor for `Dialog`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List dialogDescriptor = $convert.base64Decode(
    'CgZEaWFsb2cSDgoCaWQYASABKAlSAmlkEicKBHR5cGUYAiABKA4yEy51bmljbGllbnQuQ2hhdF'
    'R5cGVSBHR5cGUSFAoFdGl0bGUYAyABKAlSBXRpdGxlEh0KCmF2YXRhcl91cmwYBCABKAlSCWF2'
    'YXRhclVybBIdCgphdmF0YXJfYjY0GAUgASgJUglhdmF0YXJCNjQSNQoMbGFzdF9tZXNzYWdlGA'
    'YgASgLMhIudW5pY2xpZW50Lk1lc3NhZ2VSC2xhc3RNZXNzYWdlEiEKDHVucmVhZF9jb3VudBgH'
    'IAEoBVILdW5yZWFkQ291bnQSGQoIaXNfbXV0ZWQYCCABKAhSB2lzTXV0ZWQSGwoJaXNfcGlubm'
    'VkGAkgASgIUghpc1Bpbm5lZBIfCgtpc19hcmNoaXZlZBgKIAEoCFIKaXNBcmNoaXZlZBIhCgxt'
    'ZW1iZXJfY291bnQYCyABKAVSC21lbWJlckNvdW50EhsKCXBhcmVudF9pZBgMIAEoCVIIcGFyZW'
    '50SWQSGgoIcGxhdGZvcm0YDSABKAlSCHBsYXRmb3Jt');

@$core.Deprecated('Use messageDescriptor instead')
const Message$json = {
  '1': 'Message',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'sender_id', '3': 3, '4': 1, '5': 9, '10': 'senderId'},
    {'1': 'sender_name', '3': 4, '4': 1, '5': 9, '10': 'senderName'},
    {'1': 'text', '3': 5, '4': 1, '5': 9, '10': 'text'},
    {'1': 'timestamp_ms', '3': 6, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'edited_at_ms', '3': 7, '4': 1, '5': 3, '10': 'editedAtMs'},
    {'1': 'status', '3': 8, '4': 1, '5': 14, '6': '.uniclient.MessageStatus', '10': 'status'},
    {'1': 'reply_to_id', '3': 9, '4': 1, '5': 9, '10': 'replyToId'},
    {'1': 'reply_preview', '3': 10, '4': 1, '5': 9, '10': 'replyPreview'},
    {'1': 'forward_from', '3': 11, '4': 1, '5': 9, '10': 'forwardFrom'},
    {'1': 'is_encrypted', '3': 12, '4': 1, '5': 8, '10': 'isEncrypted'},
    {'1': 'decrypt_failed', '3': 13, '4': 1, '5': 8, '10': 'decryptFailed'},
    {'1': 'attachments', '3': 14, '4': 3, '5': 11, '6': '.uniclient.FileRef', '10': 'attachments'},
    {'1': 'reactions', '3': 15, '4': 3, '5': 11, '6': '.uniclient.Reaction', '10': 'reactions'},
    {'1': 'is_pinned', '3': 16, '4': 1, '5': 8, '10': 'isPinned'},
    {'1': 'platform', '3': 17, '4': 1, '5': 9, '10': 'platform'},
    {'1': 'extra_json', '3': 18, '4': 1, '5': 12, '10': 'extraJson'},
  ],
};

/// Descriptor for `Message`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List messageDescriptor = $convert.base64Decode(
    'CgdNZXNzYWdlEg4KAmlkGAEgASgJUgJpZBIXCgdjaGF0X2lkGAIgASgJUgZjaGF0SWQSGwoJc2'
    'VuZGVyX2lkGAMgASgJUghzZW5kZXJJZBIfCgtzZW5kZXJfbmFtZRgEIAEoCVIKc2VuZGVyTmFt'
    'ZRISCgR0ZXh0GAUgASgJUgR0ZXh0EiEKDHRpbWVzdGFtcF9tcxgGIAEoA1ILdGltZXN0YW1wTX'
    'MSIAoMZWRpdGVkX2F0X21zGAcgASgDUgplZGl0ZWRBdE1zEjAKBnN0YXR1cxgIIAEoDjIYLnVu'
    'aWNsaWVudC5NZXNzYWdlU3RhdHVzUgZzdGF0dXMSHgoLcmVwbHlfdG9faWQYCSABKAlSCXJlcG'
    'x5VG9JZBIjCg1yZXBseV9wcmV2aWV3GAogASgJUgxyZXBseVByZXZpZXcSIQoMZm9yd2FyZF9m'
    'cm9tGAsgASgJUgtmb3J3YXJkRnJvbRIhCgxpc19lbmNyeXB0ZWQYDCABKAhSC2lzRW5jcnlwdG'
    'VkEiUKDmRlY3J5cHRfZmFpbGVkGA0gASgIUg1kZWNyeXB0RmFpbGVkEjQKC2F0dGFjaG1lbnRz'
    'GA4gAygLMhIudW5pY2xpZW50LkZpbGVSZWZSC2F0dGFjaG1lbnRzEjEKCXJlYWN0aW9ucxgPIA'
    'MoCzITLnVuaWNsaWVudC5SZWFjdGlvblIJcmVhY3Rpb25zEhsKCWlzX3Bpbm5lZBgQIAEoCFII'
    'aXNQaW5uZWQSGgoIcGxhdGZvcm0YESABKAlSCHBsYXRmb3JtEh0KCmV4dHJhX2pzb24YEiABKA'
    'xSCWV4dHJhSnNvbg==');

@$core.Deprecated('Use outgoingMessageDescriptor instead')
const OutgoingMessage$json = {
  '1': 'OutgoingMessage',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'reply_to_id', '3': 2, '4': 1, '5': 9, '10': 'replyToId'},
    {'1': 'attachments', '3': 3, '4': 3, '5': 11, '6': '.uniclient.FileRef', '10': 'attachments'},
    {'1': 'extra_json', '3': 4, '4': 1, '5': 12, '10': 'extraJson'},
  ],
};

/// Descriptor for `OutgoingMessage`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List outgoingMessageDescriptor = $convert.base64Decode(
    'Cg9PdXRnb2luZ01lc3NhZ2USEgoEdGV4dBgBIAEoCVIEdGV4dBIeCgtyZXBseV90b19pZBgCIA'
    'EoCVIJcmVwbHlUb0lkEjQKC2F0dGFjaG1lbnRzGAMgAygLMhIudW5pY2xpZW50LkZpbGVSZWZS'
    'C2F0dGFjaG1lbnRzEh0KCmV4dHJhX2pzb24YBCABKAxSCWV4dHJhSnNvbg==');

@$core.Deprecated('Use fileRefDescriptor instead')
const FileRef$json = {
  '1': 'FileRef',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'mime_type', '3': 3, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'size', '3': 4, '4': 1, '5': 3, '10': 'size'},
    {'1': 'url', '3': 5, '4': 1, '5': 9, '10': 'url'},
    {'1': 'thumb_b64', '3': 6, '4': 1, '5': 9, '10': 'thumbB64'},
    {'1': 'extra', '3': 7, '4': 1, '5': 9, '10': 'extra'},
  ],
};

/// Descriptor for `FileRef`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileRefDescriptor = $convert.base64Decode(
    'CgdGaWxlUmVmEg4KAmlkGAEgASgJUgJpZBISCgRuYW1lGAIgASgJUgRuYW1lEhsKCW1pbWVfdH'
    'lwZRgDIAEoCVIIbWltZVR5cGUSEgoEc2l6ZRgEIAEoA1IEc2l6ZRIQCgN1cmwYBSABKAlSA3Vy'
    'bBIbCgl0aHVtYl9iNjQYBiABKAlSCHRodW1iQjY0EhQKBWV4dHJhGAcgASgJUgVleHRyYQ==');

@$core.Deprecated('Use fileUploadRequestDescriptor instead')
const FileUploadRequest$json = {
  '1': 'FileUploadRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {'1': 'mime_type', '3': 2, '4': 1, '5': 9, '10': 'mimeType'},
    {'1': 'size', '3': 3, '4': 1, '5': 3, '10': 'size'},
    {'1': 'file_path', '3': 4, '4': 1, '5': 9, '10': 'filePath'},
  ],
};

/// Descriptor for `FileUploadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileUploadRequestDescriptor = $convert.base64Decode(
    'ChFGaWxlVXBsb2FkUmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lEhsKCW1pbWVfdHlwZRgCIA'
    'EoCVIIbWltZVR5cGUSEgoEc2l6ZRgDIAEoA1IEc2l6ZRIbCglmaWxlX3BhdGgYBCABKAlSCGZp'
    'bGVQYXRo');

@$core.Deprecated('Use reactionDescriptor instead')
const Reaction$json = {
  '1': 'Reaction',
  '2': [
    {'1': 'emoji', '3': 1, '4': 1, '5': 9, '10': 'emoji'},
    {'1': 'count', '3': 2, '4': 1, '5': 5, '10': 'count'},
    {'1': 'by_me', '3': 3, '4': 1, '5': 8, '10': 'byMe'},
  ],
};

/// Descriptor for `Reaction`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List reactionDescriptor = $convert.base64Decode(
    'CghSZWFjdGlvbhIUCgVlbW9qaRgBIAEoCVIFZW1vamkSFAoFY291bnQYAiABKAVSBWNvdW50Eh'
    'MKBWJ5X21lGAMgASgIUgRieU1l');

@$core.Deprecated('Use readStateDescriptor instead')
const ReadState$json = {
  '1': 'ReadState',
  '2': [
    {'1': 'my_last_read', '3': 1, '4': 1, '5': 9, '10': 'myLastRead'},
    {'1': 'peer_last_read', '3': 2, '4': 3, '5': 11, '6': '.uniclient.ReadState.PeerLastReadEntry', '10': 'peerLastRead'},
  ],
  '3': [ReadState_PeerLastReadEntry$json],
};

@$core.Deprecated('Use readStateDescriptor instead')
const ReadState_PeerLastReadEntry$json = {
  '1': 'PeerLastReadEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `ReadState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List readStateDescriptor = $convert.base64Decode(
    'CglSZWFkU3RhdGUSIAoMbXlfbGFzdF9yZWFkGAEgASgJUgpteUxhc3RSZWFkEkwKDnBlZXJfbG'
    'FzdF9yZWFkGAIgAygLMiYudW5pY2xpZW50LlJlYWRTdGF0ZS5QZWVyTGFzdFJlYWRFbnRyeVIM'
    'cGVlckxhc3RSZWFkGj8KEVBlZXJMYXN0UmVhZEVudHJ5EhAKA2tleRgBIAEoCVIDa2V5EhQKBX'
    'ZhbHVlGAIgASgJUgV2YWx1ZToCOAE=');

@$core.Deprecated('Use callSessionDescriptor instead')
const CallSession$json = {
  '1': 'CallSession',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'is_video', '3': 3, '4': 1, '5': 8, '10': 'isVideo'},
    {'1': 'is_group', '3': 4, '4': 1, '5': 8, '10': 'isGroup'},
    {'1': 'participants', '3': 5, '4': 3, '5': 11, '6': '.uniclient.CallParticipant', '10': 'participants'},
    {'1': 'state', '3': 6, '4': 1, '5': 14, '6': '.uniclient.CallState', '10': 'state'},
    {'1': 'meta', '3': 7, '4': 3, '5': 11, '6': '.uniclient.CallSession.MetaEntry', '10': 'meta'},
  ],
  '3': [CallSession_MetaEntry$json],
};

@$core.Deprecated('Use callSessionDescriptor instead')
const CallSession_MetaEntry$json = {
  '1': 'MetaEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `CallSession`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callSessionDescriptor = $convert.base64Decode(
    'CgtDYWxsU2Vzc2lvbhIOCgJpZBgBIAEoCVICaWQSFwoHY2hhdF9pZBgCIAEoCVIGY2hhdElkEh'
    'kKCGlzX3ZpZGVvGAMgASgIUgdpc1ZpZGVvEhkKCGlzX2dyb3VwGAQgASgIUgdpc0dyb3VwEj4K'
    'DHBhcnRpY2lwYW50cxgFIAMoCzIaLnVuaWNsaWVudC5DYWxsUGFydGljaXBhbnRSDHBhcnRpY2'
    'lwYW50cxIqCgVzdGF0ZRgGIAEoDjIULnVuaWNsaWVudC5DYWxsU3RhdGVSBXN0YXRlEjQKBG1l'
    'dGEYByADKAsyIC51bmljbGllbnQuQ2FsbFNlc3Npb24uTWV0YUVudHJ5UgRtZXRhGjcKCU1ldG'
    'FFbnRyeRIQCgNrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWU6AjgB');

@$core.Deprecated('Use callParticipantDescriptor instead')
const CallParticipant$json = {
  '1': 'CallParticipant',
  '2': [
    {'1': 'user_id', '3': 1, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'display_name', '3': 2, '4': 1, '5': 9, '10': 'displayName'},
    {'1': 'is_muted', '3': 3, '4': 1, '5': 8, '10': 'isMuted'},
    {'1': 'is_speaking', '3': 4, '4': 1, '5': 8, '10': 'isSpeaking'},
    {'1': 'has_video', '3': 5, '4': 1, '5': 8, '10': 'hasVideo'},
  ],
};

/// Descriptor for `CallParticipant`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List callParticipantDescriptor = $convert.base64Decode(
    'Cg9DYWxsUGFydGljaXBhbnQSFwoHdXNlcl9pZBgBIAEoCVIGdXNlcklkEiEKDGRpc3BsYXlfbm'
    'FtZRgCIAEoCVILZGlzcGxheU5hbWUSGQoIaXNfbXV0ZWQYAyABKAhSB2lzTXV0ZWQSHwoLaXNf'
    'c3BlYWtpbmcYBCABKAhSCmlzU3BlYWtpbmcSGwoJaGFzX3ZpZGVvGAUgASgIUghoYXNWaWRlbw'
    '==');

@$core.Deprecated('Use folderDescriptor instead')
const Folder$json = {
  '1': 'Folder',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'name', '3': 2, '4': 1, '5': 9, '10': 'name'},
    {'1': 'chat_ids', '3': 3, '4': 3, '5': 9, '10': 'chatIds'},
  ],
};

/// Descriptor for `Folder`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List folderDescriptor = $convert.base64Decode(
    'CgZGb2xkZXISDgoCaWQYASABKAlSAmlkEhIKBG5hbWUYAiABKAlSBG5hbWUSGQoIY2hhdF9pZH'
    'MYAyADKAlSB2NoYXRJZHM=');

@$core.Deprecated('Use sessionDescriptor instead')
const Session$json = {
  '1': 'Session',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {'1': 'device', '3': 2, '4': 1, '5': 9, '10': 'device'},
    {'1': 'platform', '3': 3, '4': 1, '5': 9, '10': 'platform'},
    {'1': 'app_name', '3': 4, '4': 1, '5': 9, '10': 'appName'},
    {'1': 'app_version', '3': 5, '4': 1, '5': 9, '10': 'appVersion'},
    {'1': 'ip', '3': 6, '4': 1, '5': 9, '10': 'ip'},
    {'1': 'location', '3': 7, '4': 1, '5': 9, '10': 'location'},
    {'1': 'last_active_ms', '3': 8, '4': 1, '5': 3, '10': 'lastActiveMs'},
    {'1': 'is_current', '3': 9, '4': 1, '5': 8, '10': 'isCurrent'},
  ],
};

/// Descriptor for `Session`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionDescriptor = $convert.base64Decode(
    'CgdTZXNzaW9uEg4KAmlkGAEgASgJUgJpZBIWCgZkZXZpY2UYAiABKAlSBmRldmljZRIaCghwbG'
    'F0Zm9ybRgDIAEoCVIIcGxhdGZvcm0SGQoIYXBwX25hbWUYBCABKAlSB2FwcE5hbWUSHwoLYXBw'
    'X3ZlcnNpb24YBSABKAlSCmFwcFZlcnNpb24SDgoCaXAYBiABKAlSAmlwEhoKCGxvY2F0aW9uGA'
    'cgASgJUghsb2NhdGlvbhIkCg5sYXN0X2FjdGl2ZV9tcxgIIAEoA1IMbGFzdEFjdGl2ZU1zEh0K'
    'CmlzX2N1cnJlbnQYCSABKAhSCWlzQ3VycmVudA==');

@$core.Deprecated('Use verificationInfoDescriptor instead')
const VerificationInfo$json = {
  '1': 'VerificationInfo',
  '2': [
    {'1': 'transaction_id', '3': 1, '4': 1, '5': 9, '10': 'transactionId'},
    {'1': 'state', '3': 2, '4': 1, '5': 9, '10': 'state'},
    {'1': 'from_user', '3': 3, '4': 1, '5': 9, '10': 'fromUser'},
    {'1': 'from_device', '3': 4, '4': 1, '5': 9, '10': 'fromDevice'},
    {'1': 'emojis', '3': 5, '4': 3, '5': 9, '10': 'emojis'},
    {'1': 'emoji_symbols', '3': 6, '4': 3, '5': 9, '10': 'emojiSymbols'},
    {'1': 'decimals', '3': 7, '4': 3, '5': 5, '10': 'decimals'},
    {'1': 'cancel_code', '3': 8, '4': 1, '5': 9, '10': 'cancelCode'},
    {'1': 'cancel_reason', '3': 9, '4': 1, '5': 9, '10': 'cancelReason'},
  ],
};

/// Descriptor for `VerificationInfo`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List verificationInfoDescriptor = $convert.base64Decode(
    'ChBWZXJpZmljYXRpb25JbmZvEiUKDnRyYW5zYWN0aW9uX2lkGAEgASgJUg10cmFuc2FjdGlvbk'
    'lkEhQKBXN0YXRlGAIgASgJUgVzdGF0ZRIbCglmcm9tX3VzZXIYAyABKAlSCGZyb21Vc2VyEh8K'
    'C2Zyb21fZGV2aWNlGAQgASgJUgpmcm9tRGV2aWNlEhYKBmVtb2ppcxgFIAMoCVIGZW1vamlzEi'
    'MKDWVtb2ppX3N5bWJvbHMYBiADKAlSDGVtb2ppU3ltYm9scxIaCghkZWNpbWFscxgHIAMoBVII'
    'ZGVjaW1hbHMSHwoLY2FuY2VsX2NvZGUYCCABKAlSCmNhbmNlbENvZGUSIwoNY2FuY2VsX3JlYX'
    'NvbhgJIAEoCVIMY2FuY2VsUmVhc29u');

@$core.Deprecated('Use updateDescriptor instead')
const Update$json = {
  '1': 'Update',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.uniclient.UpdateType', '10': 'type'},
    {'1': 'chat_id', '3': 2, '4': 1, '5': 9, '10': 'chatId'},
    {'1': 'message', '3': 3, '4': 1, '5': 11, '6': '.uniclient.Message', '10': 'message'},
    {'1': 'message_id', '3': 4, '4': 1, '5': 9, '10': 'messageId'},
    {'1': 'user_id', '3': 5, '4': 1, '5': 9, '10': 'userId'},
    {'1': 'read_state', '3': 6, '4': 1, '5': 11, '6': '.uniclient.ReadState', '10': 'readState'},
    {'1': 'call', '3': 7, '4': 1, '5': 11, '6': '.uniclient.CallSession', '10': 'call'},
    {'1': 'is_online', '3': 8, '4': 1, '5': 8, '10': 'isOnline'},
    {'1': 'has_is_online', '3': 9, '4': 1, '5': 8, '10': 'hasIsOnline'},
    {'1': 'verification', '3': 10, '4': 1, '5': 11, '6': '.uniclient.VerificationInfo', '10': 'verification'},
    {'1': 'conn_state', '3': 11, '4': 1, '5': 9, '10': 'connState'},
    {'1': 'platform', '3': 12, '4': 1, '5': 9, '10': 'platform'},
  ],
};

/// Descriptor for `Update`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateDescriptor = $convert.base64Decode(
    'CgZVcGRhdGUSKQoEdHlwZRgBIAEoDjIVLnVuaWNsaWVudC5VcGRhdGVUeXBlUgR0eXBlEhcKB2'
    'NoYXRfaWQYAiABKAlSBmNoYXRJZBIsCgdtZXNzYWdlGAMgASgLMhIudW5pY2xpZW50Lk1lc3Nh'
    'Z2VSB21lc3NhZ2USHQoKbWVzc2FnZV9pZBgEIAEoCVIJbWVzc2FnZUlkEhcKB3VzZXJfaWQYBS'
    'ABKAlSBnVzZXJJZBIzCgpyZWFkX3N0YXRlGAYgASgLMhQudW5pY2xpZW50LlJlYWRTdGF0ZVIJ'
    'cmVhZFN0YXRlEioKBGNhbGwYByABKAsyFi51bmljbGllbnQuQ2FsbFNlc3Npb25SBGNhbGwSGw'
    'oJaXNfb25saW5lGAggASgIUghpc09ubGluZRIiCg1oYXNfaXNfb25saW5lGAkgASgIUgtoYXNJ'
    'c09ubGluZRI/Cgx2ZXJpZmljYXRpb24YCiABKAsyGy51bmljbGllbnQuVmVyaWZpY2F0aW9uSW'
    '5mb1IMdmVyaWZpY2F0aW9uEh0KCmNvbm5fc3RhdGUYCyABKAlSCWNvbm5TdGF0ZRIaCghwbGF0'
    'Zm9ybRgMIAEoCVIIcGxhdGZvcm0=');

@$core.Deprecated('Use bridgeRequestDescriptor instead')
const BridgeRequest$json = {
  '1': 'BridgeRequest',
  '2': [
    {'1': 'core_id', '3': 1, '4': 1, '5': 9, '10': 'coreId'},
    {'1': 'method', '3': 2, '4': 1, '5': 9, '10': 'method'},
    {'1': 'payload', '3': 3, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `BridgeRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bridgeRequestDescriptor = $convert.base64Decode(
    'Cg1CcmlkZ2VSZXF1ZXN0EhcKB2NvcmVfaWQYASABKAlSBmNvcmVJZBIWCgZtZXRob2QYAiABKA'
    'lSBm1ldGhvZBIYCgdwYXlsb2FkGAMgASgMUgdwYXlsb2Fk');

@$core.Deprecated('Use bridgeResponseDescriptor instead')
const BridgeResponse$json = {
  '1': 'BridgeResponse',
  '2': [
    {'1': 'ok', '3': 1, '4': 1, '5': 8, '10': 'ok'},
    {'1': 'error', '3': 2, '4': 1, '5': 9, '10': 'error'},
    {'1': 'error_code', '3': 3, '4': 1, '5': 9, '10': 'errorCode'},
    {'1': 'payload', '3': 4, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `BridgeResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bridgeResponseDescriptor = $convert.base64Decode(
    'Cg5CcmlkZ2VSZXNwb25zZRIOCgJvaxgBIAEoCFICb2sSFAoFZXJyb3IYAiABKAlSBWVycm9yEh'
    '0KCmVycm9yX2NvZGUYAyABKAlSCWVycm9yQ29kZRIYCgdwYXlsb2FkGAQgASgMUgdwYXlsb2Fk');

@$core.Deprecated('Use bridgeEventDescriptor instead')
const BridgeEvent$json = {
  '1': 'BridgeEvent',
  '2': [
    {'1': 'core_id', '3': 1, '4': 1, '5': 9, '10': 'coreId'},
    {'1': 'update', '3': 2, '4': 1, '5': 11, '6': '.uniclient.Update', '10': 'update'},
    {'1': 'engine_event', '3': 3, '4': 1, '5': 12, '10': 'engineEvent'},
  ],
};

/// Descriptor for `BridgeEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List bridgeEventDescriptor = $convert.base64Decode(
    'CgtCcmlkZ2VFdmVudBIXCgdjb3JlX2lkGAEgASgJUgZjb3JlSWQSKQoGdXBkYXRlGAIgASgLMh'
    'EudW5pY2xpZW50LlVwZGF0ZVIGdXBkYXRlEiEKDGVuZ2luZV9ldmVudBgDIAEoDFILZW5naW5l'
    'RXZlbnQ=');


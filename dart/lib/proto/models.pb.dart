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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'models.pbenum.dart';

export 'models.pbenum.dart';

class AuthConfig extends $pb.GeneratedMessage {
  factory AuthConfig({
    AuthMode? mode,
    $core.String? botToken,
    $core.String? phone,
    $core.String? otp,
    $core.String? password2f,
    $core.Map<$core.String, $core.String>? extra,
  }) {
    final $result = create();
    if (mode != null) {
      $result.mode = mode;
    }
    if (botToken != null) {
      $result.botToken = botToken;
    }
    if (phone != null) {
      $result.phone = phone;
    }
    if (otp != null) {
      $result.otp = otp;
    }
    if (password2f != null) {
      $result.password2f = password2f;
    }
    if (extra != null) {
      $result.extra.addAll(extra);
    }
    return $result;
  }
  AuthConfig._() : super();
  factory AuthConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AuthConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AuthConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..e<AuthMode>(1, _omitFieldNames ? '' : 'mode', $pb.PbFieldType.OE, defaultOrMaker: AuthMode.AUTH_MODE_UNSPECIFIED, valueOf: AuthMode.valueOf, enumValues: AuthMode.values)
    ..aOS(2, _omitFieldNames ? '' : 'botToken')
    ..aOS(3, _omitFieldNames ? '' : 'phone')
    ..aOS(4, _omitFieldNames ? '' : 'otp')
    ..aOS(5, _omitFieldNames ? '' : 'password2f', protoName: 'password_2f')
    ..m<$core.String, $core.String>(6, _omitFieldNames ? '' : 'extra', entryClassName: 'AuthConfig.ExtraEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('uniclient'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AuthConfig clone() => AuthConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AuthConfig copyWith(void Function(AuthConfig) updates) => super.copyWith((message) => updates(message as AuthConfig)) as AuthConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuthConfig create() => AuthConfig._();
  AuthConfig createEmptyInstance() => create();
  static $pb.PbList<AuthConfig> createRepeated() => $pb.PbList<AuthConfig>();
  @$core.pragma('dart2js:noInline')
  static AuthConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AuthConfig>(create);
  static AuthConfig? _defaultInstance;

  @$pb.TagNumber(1)
  AuthMode get mode => $_getN(0);
  @$pb.TagNumber(1)
  set mode(AuthMode v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get botToken => $_getSZ(1);
  @$pb.TagNumber(2)
  set botToken($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasBotToken() => $_has(1);
  @$pb.TagNumber(2)
  void clearBotToken() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get phone => $_getSZ(2);
  @$pb.TagNumber(3)
  set phone($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPhone() => $_has(2);
  @$pb.TagNumber(3)
  void clearPhone() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get otp => $_getSZ(3);
  @$pb.TagNumber(4)
  set otp($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOtp() => $_has(3);
  @$pb.TagNumber(4)
  void clearOtp() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get password2f => $_getSZ(4);
  @$pb.TagNumber(5)
  set password2f($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPassword2f() => $_has(4);
  @$pb.TagNumber(5)
  void clearPassword2f() => clearField(5);

  @$pb.TagNumber(6)
  $core.Map<$core.String, $core.String> get extra => $_getMap(5);
}

class PaginationOpts extends $pb.GeneratedMessage {
  factory PaginationOpts({
    $core.int? limit,
    $core.String? offset,
  }) {
    final $result = create();
    if (limit != null) {
      $result.limit = limit;
    }
    if (offset != null) {
      $result.offset = offset;
    }
    return $result;
  }
  PaginationOpts._() : super();
  factory PaginationOpts.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PaginationOpts.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PaginationOpts', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.O3)
    ..aOS(2, _omitFieldNames ? '' : 'offset')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PaginationOpts clone() => PaginationOpts()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PaginationOpts copyWith(void Function(PaginationOpts) updates) => super.copyWith((message) => updates(message as PaginationOpts)) as PaginationOpts;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PaginationOpts create() => PaginationOpts._();
  PaginationOpts createEmptyInstance() => create();
  static $pb.PbList<PaginationOpts> createRepeated() => $pb.PbList<PaginationOpts>();
  @$core.pragma('dart2js:noInline')
  static PaginationOpts getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PaginationOpts>(create);
  static PaginationOpts? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get limit => $_getIZ(0);
  @$pb.TagNumber(1)
  set limit($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLimit() => $_has(0);
  @$pb.TagNumber(1)
  void clearLimit() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get offset => $_getSZ(1);
  @$pb.TagNumber(2)
  set offset($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasOffset() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffset() => clearField(2);
}

class User extends $pb.GeneratedMessage {
  factory User({
    $core.String? id,
    $core.String? username,
    $core.String? displayName,
    $core.String? phone,
    $core.String? avatarUrl,
    $core.String? avatarB64,
    $core.bool? isBot,
    $core.bool? isOnline,
    $fixnum.Int64? lastSeenMs,
    $core.String? platform,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (username != null) {
      $result.username = username;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (phone != null) {
      $result.phone = phone;
    }
    if (avatarUrl != null) {
      $result.avatarUrl = avatarUrl;
    }
    if (avatarB64 != null) {
      $result.avatarB64 = avatarB64;
    }
    if (isBot != null) {
      $result.isBot = isBot;
    }
    if (isOnline != null) {
      $result.isOnline = isOnline;
    }
    if (lastSeenMs != null) {
      $result.lastSeenMs = lastSeenMs;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    return $result;
  }
  User._() : super();
  factory User.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory User.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'User', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'displayName')
    ..aOS(4, _omitFieldNames ? '' : 'phone')
    ..aOS(5, _omitFieldNames ? '' : 'avatarUrl')
    ..aOS(6, _omitFieldNames ? '' : 'avatarB64')
    ..aOB(7, _omitFieldNames ? '' : 'isBot')
    ..aOB(8, _omitFieldNames ? '' : 'isOnline')
    ..aInt64(9, _omitFieldNames ? '' : 'lastSeenMs')
    ..aOS(10, _omitFieldNames ? '' : 'platform')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  User clone() => User()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  User copyWith(void Function(User) updates) => super.copyWith((message) => updates(message as User)) as User;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static User create() => User._();
  User createEmptyInstance() => create();
  static $pb.PbList<User> createRepeated() => $pb.PbList<User>();
  @$core.pragma('dart2js:noInline')
  static User getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<User>(create);
  static User? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get username => $_getSZ(1);
  @$pb.TagNumber(2)
  set username($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUsername() => $_has(1);
  @$pb.TagNumber(2)
  void clearUsername() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get displayName => $_getSZ(2);
  @$pb.TagNumber(3)
  set displayName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDisplayName() => $_has(2);
  @$pb.TagNumber(3)
  void clearDisplayName() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get phone => $_getSZ(3);
  @$pb.TagNumber(4)
  set phone($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPhone() => $_has(3);
  @$pb.TagNumber(4)
  void clearPhone() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get avatarUrl => $_getSZ(4);
  @$pb.TagNumber(5)
  set avatarUrl($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAvatarUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvatarUrl() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get avatarB64 => $_getSZ(5);
  @$pb.TagNumber(6)
  set avatarB64($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasAvatarB64() => $_has(5);
  @$pb.TagNumber(6)
  void clearAvatarB64() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isBot => $_getBF(6);
  @$pb.TagNumber(7)
  set isBot($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsBot() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsBot() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get isOnline => $_getBF(7);
  @$pb.TagNumber(8)
  set isOnline($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasIsOnline() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsOnline() => clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get lastSeenMs => $_getI64(8);
  @$pb.TagNumber(9)
  set lastSeenMs($fixnum.Int64 v) { $_setInt64(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasLastSeenMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearLastSeenMs() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get platform => $_getSZ(9);
  @$pb.TagNumber(10)
  set platform($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasPlatform() => $_has(9);
  @$pb.TagNumber(10)
  void clearPlatform() => clearField(10);
}

class Dialog extends $pb.GeneratedMessage {
  factory Dialog({
    $core.String? id,
    ChatType? type,
    $core.String? title,
    $core.String? avatarUrl,
    $core.String? avatarB64,
    Message? lastMessage,
    $core.int? unreadCount,
    $core.bool? isMuted,
    $core.bool? isPinned,
    $core.bool? isArchived,
    $core.int? memberCount,
    $core.String? parentId,
    $core.String? platform,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (type != null) {
      $result.type = type;
    }
    if (title != null) {
      $result.title = title;
    }
    if (avatarUrl != null) {
      $result.avatarUrl = avatarUrl;
    }
    if (avatarB64 != null) {
      $result.avatarB64 = avatarB64;
    }
    if (lastMessage != null) {
      $result.lastMessage = lastMessage;
    }
    if (unreadCount != null) {
      $result.unreadCount = unreadCount;
    }
    if (isMuted != null) {
      $result.isMuted = isMuted;
    }
    if (isPinned != null) {
      $result.isPinned = isPinned;
    }
    if (isArchived != null) {
      $result.isArchived = isArchived;
    }
    if (memberCount != null) {
      $result.memberCount = memberCount;
    }
    if (parentId != null) {
      $result.parentId = parentId;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    return $result;
  }
  Dialog._() : super();
  factory Dialog.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Dialog.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Dialog', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..e<ChatType>(2, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: ChatType.CHAT_TYPE_UNSPECIFIED, valueOf: ChatType.valueOf, enumValues: ChatType.values)
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..aOS(4, _omitFieldNames ? '' : 'avatarUrl')
    ..aOS(5, _omitFieldNames ? '' : 'avatarB64')
    ..aOM<Message>(6, _omitFieldNames ? '' : 'lastMessage', subBuilder: Message.create)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'unreadCount', $pb.PbFieldType.O3)
    ..aOB(8, _omitFieldNames ? '' : 'isMuted')
    ..aOB(9, _omitFieldNames ? '' : 'isPinned')
    ..aOB(10, _omitFieldNames ? '' : 'isArchived')
    ..a<$core.int>(11, _omitFieldNames ? '' : 'memberCount', $pb.PbFieldType.O3)
    ..aOS(12, _omitFieldNames ? '' : 'parentId')
    ..aOS(13, _omitFieldNames ? '' : 'platform')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Dialog clone() => Dialog()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Dialog copyWith(void Function(Dialog) updates) => super.copyWith((message) => updates(message as Dialog)) as Dialog;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Dialog create() => Dialog._();
  Dialog createEmptyInstance() => create();
  static $pb.PbList<Dialog> createRepeated() => $pb.PbList<Dialog>();
  @$core.pragma('dart2js:noInline')
  static Dialog getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Dialog>(create);
  static Dialog? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  ChatType get type => $_getN(1);
  @$pb.TagNumber(2)
  set type(ChatType v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTitle() => $_has(2);
  @$pb.TagNumber(3)
  void clearTitle() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get avatarUrl => $_getSZ(3);
  @$pb.TagNumber(4)
  set avatarUrl($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAvatarUrl() => $_has(3);
  @$pb.TagNumber(4)
  void clearAvatarUrl() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get avatarB64 => $_getSZ(4);
  @$pb.TagNumber(5)
  set avatarB64($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAvatarB64() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvatarB64() => clearField(5);

  @$pb.TagNumber(6)
  Message get lastMessage => $_getN(5);
  @$pb.TagNumber(6)
  set lastMessage(Message v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasLastMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastMessage() => clearField(6);
  @$pb.TagNumber(6)
  Message ensureLastMessage() => $_ensure(5);

  @$pb.TagNumber(7)
  $core.int get unreadCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set unreadCount($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasUnreadCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearUnreadCount() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get isMuted => $_getBF(7);
  @$pb.TagNumber(8)
  set isMuted($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasIsMuted() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsMuted() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get isPinned => $_getBF(8);
  @$pb.TagNumber(9)
  set isPinned($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasIsPinned() => $_has(8);
  @$pb.TagNumber(9)
  void clearIsPinned() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get isArchived => $_getBF(9);
  @$pb.TagNumber(10)
  set isArchived($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasIsArchived() => $_has(9);
  @$pb.TagNumber(10)
  void clearIsArchived() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get memberCount => $_getIZ(10);
  @$pb.TagNumber(11)
  set memberCount($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasMemberCount() => $_has(10);
  @$pb.TagNumber(11)
  void clearMemberCount() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get parentId => $_getSZ(11);
  @$pb.TagNumber(12)
  set parentId($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasParentId() => $_has(11);
  @$pb.TagNumber(12)
  void clearParentId() => clearField(12);

  @$pb.TagNumber(13)
  $core.String get platform => $_getSZ(12);
  @$pb.TagNumber(13)
  set platform($core.String v) { $_setString(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasPlatform() => $_has(12);
  @$pb.TagNumber(13)
  void clearPlatform() => clearField(13);
}

class Message extends $pb.GeneratedMessage {
  factory Message({
    $core.String? id,
    $core.String? chatId,
    $core.String? senderId,
    $core.String? senderName,
    $core.String? text,
    $fixnum.Int64? timestampMs,
    $fixnum.Int64? editedAtMs,
    MessageStatus? status,
    $core.String? replyToId,
    $core.String? replyPreview,
    $core.String? forwardFrom,
    $core.bool? isEncrypted,
    $core.bool? decryptFailed,
    $core.Iterable<FileRef>? attachments,
    $core.Iterable<Reaction>? reactions,
    $core.bool? isPinned,
    $core.String? platform,
    $core.List<$core.int>? extraJson,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (senderId != null) {
      $result.senderId = senderId;
    }
    if (senderName != null) {
      $result.senderName = senderName;
    }
    if (text != null) {
      $result.text = text;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (editedAtMs != null) {
      $result.editedAtMs = editedAtMs;
    }
    if (status != null) {
      $result.status = status;
    }
    if (replyToId != null) {
      $result.replyToId = replyToId;
    }
    if (replyPreview != null) {
      $result.replyPreview = replyPreview;
    }
    if (forwardFrom != null) {
      $result.forwardFrom = forwardFrom;
    }
    if (isEncrypted != null) {
      $result.isEncrypted = isEncrypted;
    }
    if (decryptFailed != null) {
      $result.decryptFailed = decryptFailed;
    }
    if (attachments != null) {
      $result.attachments.addAll(attachments);
    }
    if (reactions != null) {
      $result.reactions.addAll(reactions);
    }
    if (isPinned != null) {
      $result.isPinned = isPinned;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    if (extraJson != null) {
      $result.extraJson = extraJson;
    }
    return $result;
  }
  Message._() : super();
  factory Message.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Message.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Message', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'senderId')
    ..aOS(4, _omitFieldNames ? '' : 'senderName')
    ..aOS(5, _omitFieldNames ? '' : 'text')
    ..aInt64(6, _omitFieldNames ? '' : 'timestampMs')
    ..aInt64(7, _omitFieldNames ? '' : 'editedAtMs')
    ..e<MessageStatus>(8, _omitFieldNames ? '' : 'status', $pb.PbFieldType.OE, defaultOrMaker: MessageStatus.MESSAGE_STATUS_UNSPECIFIED, valueOf: MessageStatus.valueOf, enumValues: MessageStatus.values)
    ..aOS(9, _omitFieldNames ? '' : 'replyToId')
    ..aOS(10, _omitFieldNames ? '' : 'replyPreview')
    ..aOS(11, _omitFieldNames ? '' : 'forwardFrom')
    ..aOB(12, _omitFieldNames ? '' : 'isEncrypted')
    ..aOB(13, _omitFieldNames ? '' : 'decryptFailed')
    ..pc<FileRef>(14, _omitFieldNames ? '' : 'attachments', $pb.PbFieldType.PM, subBuilder: FileRef.create)
    ..pc<Reaction>(15, _omitFieldNames ? '' : 'reactions', $pb.PbFieldType.PM, subBuilder: Reaction.create)
    ..aOB(16, _omitFieldNames ? '' : 'isPinned')
    ..aOS(17, _omitFieldNames ? '' : 'platform')
    ..a<$core.List<$core.int>>(18, _omitFieldNames ? '' : 'extraJson', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Message clone() => Message()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Message copyWith(void Function(Message) updates) => super.copyWith((message) => updates(message as Message)) as Message;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Message create() => Message._();
  Message createEmptyInstance() => create();
  static $pb.PbList<Message> createRepeated() => $pb.PbList<Message>();
  @$core.pragma('dart2js:noInline')
  static Message getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Message>(create);
  static Message? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get senderId => $_getSZ(2);
  @$pb.TagNumber(3)
  set senderId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSenderId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSenderId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get senderName => $_getSZ(3);
  @$pb.TagNumber(4)
  set senderName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSenderName() => $_has(3);
  @$pb.TagNumber(4)
  void clearSenderName() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get text => $_getSZ(4);
  @$pb.TagNumber(5)
  set text($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasText() => $_has(4);
  @$pb.TagNumber(5)
  void clearText() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get timestampMs => $_getI64(5);
  @$pb.TagNumber(6)
  set timestampMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTimestampMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimestampMs() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get editedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set editedAtMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEditedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearEditedAtMs() => clearField(7);

  @$pb.TagNumber(8)
  MessageStatus get status => $_getN(7);
  @$pb.TagNumber(8)
  set status(MessageStatus v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasStatus() => $_has(7);
  @$pb.TagNumber(8)
  void clearStatus() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get replyToId => $_getSZ(8);
  @$pb.TagNumber(9)
  set replyToId($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasReplyToId() => $_has(8);
  @$pb.TagNumber(9)
  void clearReplyToId() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get replyPreview => $_getSZ(9);
  @$pb.TagNumber(10)
  set replyPreview($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasReplyPreview() => $_has(9);
  @$pb.TagNumber(10)
  void clearReplyPreview() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get forwardFrom => $_getSZ(10);
  @$pb.TagNumber(11)
  set forwardFrom($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasForwardFrom() => $_has(10);
  @$pb.TagNumber(11)
  void clearForwardFrom() => clearField(11);

  @$pb.TagNumber(12)
  $core.bool get isEncrypted => $_getBF(11);
  @$pb.TagNumber(12)
  set isEncrypted($core.bool v) { $_setBool(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasIsEncrypted() => $_has(11);
  @$pb.TagNumber(12)
  void clearIsEncrypted() => clearField(12);

  @$pb.TagNumber(13)
  $core.bool get decryptFailed => $_getBF(12);
  @$pb.TagNumber(13)
  set decryptFailed($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasDecryptFailed() => $_has(12);
  @$pb.TagNumber(13)
  void clearDecryptFailed() => clearField(13);

  @$pb.TagNumber(14)
  $core.List<FileRef> get attachments => $_getList(13);

  @$pb.TagNumber(15)
  $core.List<Reaction> get reactions => $_getList(14);

  @$pb.TagNumber(16)
  $core.bool get isPinned => $_getBF(15);
  @$pb.TagNumber(16)
  set isPinned($core.bool v) { $_setBool(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasIsPinned() => $_has(15);
  @$pb.TagNumber(16)
  void clearIsPinned() => clearField(16);

  @$pb.TagNumber(17)
  $core.String get platform => $_getSZ(16);
  @$pb.TagNumber(17)
  set platform($core.String v) { $_setString(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasPlatform() => $_has(16);
  @$pb.TagNumber(17)
  void clearPlatform() => clearField(17);

  @$pb.TagNumber(18)
  $core.List<$core.int> get extraJson => $_getN(17);
  @$pb.TagNumber(18)
  set extraJson($core.List<$core.int> v) { $_setBytes(17, v); }
  @$pb.TagNumber(18)
  $core.bool hasExtraJson() => $_has(17);
  @$pb.TagNumber(18)
  void clearExtraJson() => clearField(18);
}

class OutgoingMessage extends $pb.GeneratedMessage {
  factory OutgoingMessage({
    $core.String? text,
    $core.String? replyToId,
    $core.Iterable<FileRef>? attachments,
    $core.List<$core.int>? extraJson,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (replyToId != null) {
      $result.replyToId = replyToId;
    }
    if (attachments != null) {
      $result.attachments.addAll(attachments);
    }
    if (extraJson != null) {
      $result.extraJson = extraJson;
    }
    return $result;
  }
  OutgoingMessage._() : super();
  factory OutgoingMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory OutgoingMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'OutgoingMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOS(2, _omitFieldNames ? '' : 'replyToId')
    ..pc<FileRef>(3, _omitFieldNames ? '' : 'attachments', $pb.PbFieldType.PM, subBuilder: FileRef.create)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'extraJson', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  OutgoingMessage clone() => OutgoingMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  OutgoingMessage copyWith(void Function(OutgoingMessage) updates) => super.copyWith((message) => updates(message as OutgoingMessage)) as OutgoingMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OutgoingMessage create() => OutgoingMessage._();
  OutgoingMessage createEmptyInstance() => create();
  static $pb.PbList<OutgoingMessage> createRepeated() => $pb.PbList<OutgoingMessage>();
  @$core.pragma('dart2js:noInline')
  static OutgoingMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OutgoingMessage>(create);
  static OutgoingMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get replyToId => $_getSZ(1);
  @$pb.TagNumber(2)
  set replyToId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasReplyToId() => $_has(1);
  @$pb.TagNumber(2)
  void clearReplyToId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<FileRef> get attachments => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<$core.int> get extraJson => $_getN(3);
  @$pb.TagNumber(4)
  set extraJson($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasExtraJson() => $_has(3);
  @$pb.TagNumber(4)
  void clearExtraJson() => clearField(4);
}

class FileRef extends $pb.GeneratedMessage {
  factory FileRef({
    $core.String? id,
    $core.String? name,
    $core.String? mimeType,
    $fixnum.Int64? size,
    $core.String? url,
    $core.String? thumbB64,
    $core.String? extra,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (name != null) {
      $result.name = name;
    }
    if (mimeType != null) {
      $result.mimeType = mimeType;
    }
    if (size != null) {
      $result.size = size;
    }
    if (url != null) {
      $result.url = url;
    }
    if (thumbB64 != null) {
      $result.thumbB64 = thumbB64;
    }
    if (extra != null) {
      $result.extra = extra;
    }
    return $result;
  }
  FileRef._() : super();
  factory FileRef.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FileRef.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FileRef', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'mimeType')
    ..aInt64(4, _omitFieldNames ? '' : 'size')
    ..aOS(5, _omitFieldNames ? '' : 'url')
    ..aOS(6, _omitFieldNames ? '' : 'thumbB64')
    ..aOS(7, _omitFieldNames ? '' : 'extra')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FileRef clone() => FileRef()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FileRef copyWith(void Function(FileRef) updates) => super.copyWith((message) => updates(message as FileRef)) as FileRef;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileRef create() => FileRef._();
  FileRef createEmptyInstance() => create();
  static $pb.PbList<FileRef> createRepeated() => $pb.PbList<FileRef>();
  @$core.pragma('dart2js:noInline')
  static FileRef getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileRef>(create);
  static FileRef? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get mimeType => $_getSZ(2);
  @$pb.TagNumber(3)
  set mimeType($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMimeType() => $_has(2);
  @$pb.TagNumber(3)
  void clearMimeType() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get size => $_getI64(3);
  @$pb.TagNumber(4)
  set size($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSize() => $_has(3);
  @$pb.TagNumber(4)
  void clearSize() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get url => $_getSZ(4);
  @$pb.TagNumber(5)
  set url($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasUrl() => $_has(4);
  @$pb.TagNumber(5)
  void clearUrl() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get thumbB64 => $_getSZ(5);
  @$pb.TagNumber(6)
  set thumbB64($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasThumbB64() => $_has(5);
  @$pb.TagNumber(6)
  void clearThumbB64() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get extra => $_getSZ(6);
  @$pb.TagNumber(7)
  set extra($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasExtra() => $_has(6);
  @$pb.TagNumber(7)
  void clearExtra() => clearField(7);
}

class FileUploadRequest extends $pb.GeneratedMessage {
  factory FileUploadRequest({
    $core.String? name,
    $core.String? mimeType,
    $fixnum.Int64? size,
    $core.String? filePath,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (mimeType != null) {
      $result.mimeType = mimeType;
    }
    if (size != null) {
      $result.size = size;
    }
    if (filePath != null) {
      $result.filePath = filePath;
    }
    return $result;
  }
  FileUploadRequest._() : super();
  factory FileUploadRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory FileUploadRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'FileUploadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'mimeType')
    ..aInt64(3, _omitFieldNames ? '' : 'size')
    ..aOS(4, _omitFieldNames ? '' : 'filePath')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  FileUploadRequest clone() => FileUploadRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  FileUploadRequest copyWith(void Function(FileUploadRequest) updates) => super.copyWith((message) => updates(message as FileUploadRequest)) as FileUploadRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FileUploadRequest create() => FileUploadRequest._();
  FileUploadRequest createEmptyInstance() => create();
  static $pb.PbList<FileUploadRequest> createRepeated() => $pb.PbList<FileUploadRequest>();
  @$core.pragma('dart2js:noInline')
  static FileUploadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FileUploadRequest>(create);
  static FileUploadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get mimeType => $_getSZ(1);
  @$pb.TagNumber(2)
  set mimeType($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMimeType() => $_has(1);
  @$pb.TagNumber(2)
  void clearMimeType() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get size => $_getI64(2);
  @$pb.TagNumber(3)
  set size($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearSize() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get filePath => $_getSZ(3);
  @$pb.TagNumber(4)
  set filePath($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFilePath() => $_has(3);
  @$pb.TagNumber(4)
  void clearFilePath() => clearField(4);
}

class Reaction extends $pb.GeneratedMessage {
  factory Reaction({
    $core.String? emoji,
    $core.int? count,
    $core.bool? byMe,
    $core.String? peerId,
    $core.String? peerName,
  }) {
    final $result = create();
    if (emoji != null) {
      $result.emoji = emoji;
    }
    if (count != null) {
      $result.count = count;
    }
    if (byMe != null) {
      $result.byMe = byMe;
    }
    if (peerId != null) {
      $result.peerId = peerId;
    }
    if (peerName != null) {
      $result.peerName = peerName;
    }
    return $result;
  }
  Reaction._() : super();
  factory Reaction.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Reaction.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Reaction', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'emoji')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'count', $pb.PbFieldType.O3)
    ..aOB(3, _omitFieldNames ? '' : 'byMe')
    ..aOS(4, _omitFieldNames ? '' : 'peerId')
    ..aOS(5, _omitFieldNames ? '' : 'peerName')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Reaction clone() => Reaction()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Reaction copyWith(void Function(Reaction) updates) => super.copyWith((message) => updates(message as Reaction)) as Reaction;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Reaction create() => Reaction._();
  Reaction createEmptyInstance() => create();
  static $pb.PbList<Reaction> createRepeated() => $pb.PbList<Reaction>();
  @$core.pragma('dart2js:noInline')
  static Reaction getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Reaction>(create);
  static Reaction? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get emoji => $_getSZ(0);
  @$pb.TagNumber(1)
  set emoji($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEmoji() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmoji() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get count => $_getIZ(1);
  @$pb.TagNumber(2)
  set count($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearCount() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get byMe => $_getBF(2);
  @$pb.TagNumber(3)
  set byMe($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasByMe() => $_has(2);
  @$pb.TagNumber(3)
  void clearByMe() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get peerId => $_getSZ(3);
  @$pb.TagNumber(4)
  set peerId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPeerId() => $_has(3);
  @$pb.TagNumber(4)
  void clearPeerId() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get peerName => $_getSZ(4);
  @$pb.TagNumber(5)
  set peerName($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPeerName() => $_has(4);
  @$pb.TagNumber(5)
  void clearPeerName() => clearField(5);
}

class ReadState extends $pb.GeneratedMessage {
  factory ReadState({
    $core.String? myLastRead,
    $core.Map<$core.String, $core.String>? peerLastRead,
  }) {
    final $result = create();
    if (myLastRead != null) {
      $result.myLastRead = myLastRead;
    }
    if (peerLastRead != null) {
      $result.peerLastRead.addAll(peerLastRead);
    }
    return $result;
  }
  ReadState._() : super();
  factory ReadState.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ReadState.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ReadState', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'myLastRead')
    ..m<$core.String, $core.String>(2, _omitFieldNames ? '' : 'peerLastRead', entryClassName: 'ReadState.PeerLastReadEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('uniclient'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ReadState clone() => ReadState()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ReadState copyWith(void Function(ReadState) updates) => super.copyWith((message) => updates(message as ReadState)) as ReadState;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReadState create() => ReadState._();
  ReadState createEmptyInstance() => create();
  static $pb.PbList<ReadState> createRepeated() => $pb.PbList<ReadState>();
  @$core.pragma('dart2js:noInline')
  static ReadState getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReadState>(create);
  static ReadState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get myLastRead => $_getSZ(0);
  @$pb.TagNumber(1)
  set myLastRead($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMyLastRead() => $_has(0);
  @$pb.TagNumber(1)
  void clearMyLastRead() => clearField(1);

  @$pb.TagNumber(2)
  $core.Map<$core.String, $core.String> get peerLastRead => $_getMap(1);
}

class CallSession extends $pb.GeneratedMessage {
  factory CallSession({
    $core.String? id,
    $core.String? chatId,
    $core.bool? isVideo,
    $core.bool? isGroup,
    $core.Iterable<CallParticipant>? participants,
    CallState? state,
    $core.Map<$core.String, $core.String>? meta,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (isVideo != null) {
      $result.isVideo = isVideo;
    }
    if (isGroup != null) {
      $result.isGroup = isGroup;
    }
    if (participants != null) {
      $result.participants.addAll(participants);
    }
    if (state != null) {
      $result.state = state;
    }
    if (meta != null) {
      $result.meta.addAll(meta);
    }
    return $result;
  }
  CallSession._() : super();
  factory CallSession.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallSession.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallSession', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOB(3, _omitFieldNames ? '' : 'isVideo')
    ..aOB(4, _omitFieldNames ? '' : 'isGroup')
    ..pc<CallParticipant>(5, _omitFieldNames ? '' : 'participants', $pb.PbFieldType.PM, subBuilder: CallParticipant.create)
    ..e<CallState>(6, _omitFieldNames ? '' : 'state', $pb.PbFieldType.OE, defaultOrMaker: CallState.CALL_STATE_UNSPECIFIED, valueOf: CallState.valueOf, enumValues: CallState.values)
    ..m<$core.String, $core.String>(7, _omitFieldNames ? '' : 'meta', entryClassName: 'CallSession.MetaEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('uniclient'))
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallSession clone() => CallSession()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallSession copyWith(void Function(CallSession) updates) => super.copyWith((message) => updates(message as CallSession)) as CallSession;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallSession create() => CallSession._();
  CallSession createEmptyInstance() => create();
  static $pb.PbList<CallSession> createRepeated() => $pb.PbList<CallSession>();
  @$core.pragma('dart2js:noInline')
  static CallSession getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallSession>(create);
  static CallSession? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get isVideo => $_getBF(2);
  @$pb.TagNumber(3)
  set isVideo($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIsVideo() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsVideo() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isGroup => $_getBF(3);
  @$pb.TagNumber(4)
  set isGroup($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsGroup() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsGroup() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<CallParticipant> get participants => $_getList(4);

  @$pb.TagNumber(6)
  CallState get state => $_getN(5);
  @$pb.TagNumber(6)
  set state(CallState v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasState() => $_has(5);
  @$pb.TagNumber(6)
  void clearState() => clearField(6);

  @$pb.TagNumber(7)
  $core.Map<$core.String, $core.String> get meta => $_getMap(6);
}

class CallParticipant extends $pb.GeneratedMessage {
  factory CallParticipant({
    $core.String? userId,
    $core.String? displayName,
    $core.bool? isMuted,
    $core.bool? isSpeaking,
    $core.bool? hasVideo,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (isMuted != null) {
      $result.isMuted = isMuted;
    }
    if (isSpeaking != null) {
      $result.isSpeaking = isSpeaking;
    }
    if (hasVideo != null) {
      $result.hasVideo = hasVideo;
    }
    return $result;
  }
  CallParticipant._() : super();
  factory CallParticipant.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory CallParticipant.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'CallParticipant', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOB(3, _omitFieldNames ? '' : 'isMuted')
    ..aOB(4, _omitFieldNames ? '' : 'isSpeaking')
    ..aOB(5, _omitFieldNames ? '' : 'hasVideo')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  CallParticipant clone() => CallParticipant()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  CallParticipant copyWith(void Function(CallParticipant) updates) => super.copyWith((message) => updates(message as CallParticipant)) as CallParticipant;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CallParticipant create() => CallParticipant._();
  CallParticipant createEmptyInstance() => create();
  static $pb.PbList<CallParticipant> createRepeated() => $pb.PbList<CallParticipant>();
  @$core.pragma('dart2js:noInline')
  static CallParticipant getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CallParticipant>(create);
  static CallParticipant? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get isMuted => $_getBF(2);
  @$pb.TagNumber(3)
  set isMuted($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIsMuted() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsMuted() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isSpeaking => $_getBF(3);
  @$pb.TagNumber(4)
  set isSpeaking($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsSpeaking() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsSpeaking() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get hasVideo => $_getBF(4);
  @$pb.TagNumber(5)
  set hasVideo($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasHasVideo() => $_has(4);
  @$pb.TagNumber(5)
  void clearHasVideo() => clearField(5);
}

class Folder extends $pb.GeneratedMessage {
  factory Folder({
    $core.String? id,
    $core.String? name,
    $core.Iterable<$core.String>? chatIds,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (name != null) {
      $result.name = name;
    }
    if (chatIds != null) {
      $result.chatIds.addAll(chatIds);
    }
    return $result;
  }
  Folder._() : super();
  factory Folder.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Folder.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Folder', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..pPS(3, _omitFieldNames ? '' : 'chatIds')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Folder clone() => Folder()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Folder copyWith(void Function(Folder) updates) => super.copyWith((message) => updates(message as Folder)) as Folder;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Folder create() => Folder._();
  Folder createEmptyInstance() => create();
  static $pb.PbList<Folder> createRepeated() => $pb.PbList<Folder>();
  @$core.pragma('dart2js:noInline')
  static Folder getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Folder>(create);
  static Folder? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.String> get chatIds => $_getList(2);
}

class Session extends $pb.GeneratedMessage {
  factory Session({
    $core.String? id,
    $core.String? device,
    $core.String? platform,
    $core.String? appName,
    $core.String? appVersion,
    $core.String? ip,
    $core.String? location,
    $fixnum.Int64? lastActiveMs,
    $core.bool? isCurrent,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (device != null) {
      $result.device = device;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    if (appName != null) {
      $result.appName = appName;
    }
    if (appVersion != null) {
      $result.appVersion = appVersion;
    }
    if (ip != null) {
      $result.ip = ip;
    }
    if (location != null) {
      $result.location = location;
    }
    if (lastActiveMs != null) {
      $result.lastActiveMs = lastActiveMs;
    }
    if (isCurrent != null) {
      $result.isCurrent = isCurrent;
    }
    return $result;
  }
  Session._() : super();
  factory Session.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Session.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Session', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'device')
    ..aOS(3, _omitFieldNames ? '' : 'platform')
    ..aOS(4, _omitFieldNames ? '' : 'appName')
    ..aOS(5, _omitFieldNames ? '' : 'appVersion')
    ..aOS(6, _omitFieldNames ? '' : 'ip')
    ..aOS(7, _omitFieldNames ? '' : 'location')
    ..aInt64(8, _omitFieldNames ? '' : 'lastActiveMs')
    ..aOB(9, _omitFieldNames ? '' : 'isCurrent')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Session clone() => Session()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Session copyWith(void Function(Session) updates) => super.copyWith((message) => updates(message as Session)) as Session;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Session create() => Session._();
  Session createEmptyInstance() => create();
  static $pb.PbList<Session> createRepeated() => $pb.PbList<Session>();
  @$core.pragma('dart2js:noInline')
  static Session getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Session>(create);
  static Session? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get device => $_getSZ(1);
  @$pb.TagNumber(2)
  set device($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDevice() => $_has(1);
  @$pb.TagNumber(2)
  void clearDevice() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get platform => $_getSZ(2);
  @$pb.TagNumber(3)
  set platform($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPlatform() => $_has(2);
  @$pb.TagNumber(3)
  void clearPlatform() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get appName => $_getSZ(3);
  @$pb.TagNumber(4)
  set appName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAppName() => $_has(3);
  @$pb.TagNumber(4)
  void clearAppName() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get appVersion => $_getSZ(4);
  @$pb.TagNumber(5)
  set appVersion($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAppVersion() => $_has(4);
  @$pb.TagNumber(5)
  void clearAppVersion() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get ip => $_getSZ(5);
  @$pb.TagNumber(6)
  set ip($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasIp() => $_has(5);
  @$pb.TagNumber(6)
  void clearIp() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get location => $_getSZ(6);
  @$pb.TagNumber(7)
  set location($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasLocation() => $_has(6);
  @$pb.TagNumber(7)
  void clearLocation() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get lastActiveMs => $_getI64(7);
  @$pb.TagNumber(8)
  set lastActiveMs($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasLastActiveMs() => $_has(7);
  @$pb.TagNumber(8)
  void clearLastActiveMs() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get isCurrent => $_getBF(8);
  @$pb.TagNumber(9)
  set isCurrent($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasIsCurrent() => $_has(8);
  @$pb.TagNumber(9)
  void clearIsCurrent() => clearField(9);
}

class VerificationInfo extends $pb.GeneratedMessage {
  factory VerificationInfo({
    $core.String? transactionId,
    $core.String? state,
    $core.String? fromUser,
    $core.String? fromDevice,
    $core.Iterable<$core.String>? emojis,
    $core.Iterable<$core.String>? emojiSymbols,
    $core.Iterable<$core.int>? decimals,
    $core.String? cancelCode,
    $core.String? cancelReason,
  }) {
    final $result = create();
    if (transactionId != null) {
      $result.transactionId = transactionId;
    }
    if (state != null) {
      $result.state = state;
    }
    if (fromUser != null) {
      $result.fromUser = fromUser;
    }
    if (fromDevice != null) {
      $result.fromDevice = fromDevice;
    }
    if (emojis != null) {
      $result.emojis.addAll(emojis);
    }
    if (emojiSymbols != null) {
      $result.emojiSymbols.addAll(emojiSymbols);
    }
    if (decimals != null) {
      $result.decimals.addAll(decimals);
    }
    if (cancelCode != null) {
      $result.cancelCode = cancelCode;
    }
    if (cancelReason != null) {
      $result.cancelReason = cancelReason;
    }
    return $result;
  }
  VerificationInfo._() : super();
  factory VerificationInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VerificationInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VerificationInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'transactionId')
    ..aOS(2, _omitFieldNames ? '' : 'state')
    ..aOS(3, _omitFieldNames ? '' : 'fromUser')
    ..aOS(4, _omitFieldNames ? '' : 'fromDevice')
    ..pPS(5, _omitFieldNames ? '' : 'emojis')
    ..pPS(6, _omitFieldNames ? '' : 'emojiSymbols')
    ..p<$core.int>(7, _omitFieldNames ? '' : 'decimals', $pb.PbFieldType.K3)
    ..aOS(8, _omitFieldNames ? '' : 'cancelCode')
    ..aOS(9, _omitFieldNames ? '' : 'cancelReason')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VerificationInfo clone() => VerificationInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VerificationInfo copyWith(void Function(VerificationInfo) updates) => super.copyWith((message) => updates(message as VerificationInfo)) as VerificationInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VerificationInfo create() => VerificationInfo._();
  VerificationInfo createEmptyInstance() => create();
  static $pb.PbList<VerificationInfo> createRepeated() => $pb.PbList<VerificationInfo>();
  @$core.pragma('dart2js:noInline')
  static VerificationInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VerificationInfo>(create);
  static VerificationInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get transactionId => $_getSZ(0);
  @$pb.TagNumber(1)
  set transactionId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTransactionId() => $_has(0);
  @$pb.TagNumber(1)
  void clearTransactionId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get state => $_getSZ(1);
  @$pb.TagNumber(2)
  set state($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get fromUser => $_getSZ(2);
  @$pb.TagNumber(3)
  set fromUser($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFromUser() => $_has(2);
  @$pb.TagNumber(3)
  void clearFromUser() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get fromDevice => $_getSZ(3);
  @$pb.TagNumber(4)
  set fromDevice($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFromDevice() => $_has(3);
  @$pb.TagNumber(4)
  void clearFromDevice() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<$core.String> get emojis => $_getList(4);

  @$pb.TagNumber(6)
  $core.List<$core.String> get emojiSymbols => $_getList(5);

  @$pb.TagNumber(7)
  $core.List<$core.int> get decimals => $_getList(6);

  @$pb.TagNumber(8)
  $core.String get cancelCode => $_getSZ(7);
  @$pb.TagNumber(8)
  set cancelCode($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasCancelCode() => $_has(7);
  @$pb.TagNumber(8)
  void clearCancelCode() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get cancelReason => $_getSZ(8);
  @$pb.TagNumber(9)
  set cancelReason($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasCancelReason() => $_has(8);
  @$pb.TagNumber(9)
  void clearCancelReason() => clearField(9);
}

class Update extends $pb.GeneratedMessage {
  factory Update({
    UpdateType? type,
    $core.String? chatId,
    Message? message,
    $core.String? messageId,
    $core.String? userId,
    ReadState? readState,
    CallSession? call,
    $core.bool? isOnline,
    $core.bool? hasIsOnline_9,
    VerificationInfo? verification,
    $core.String? connState,
    $core.String? platform,
  }) {
    final $result = create();
    if (type != null) {
      $result.type = type;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (message != null) {
      $result.message = message;
    }
    if (messageId != null) {
      $result.messageId = messageId;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    if (readState != null) {
      $result.readState = readState;
    }
    if (call != null) {
      $result.call = call;
    }
    if (isOnline != null) {
      $result.isOnline = isOnline;
    }
    if (hasIsOnline_9 != null) {
      $result.hasIsOnline_9 = hasIsOnline_9;
    }
    if (verification != null) {
      $result.verification = verification;
    }
    if (connState != null) {
      $result.connState = connState;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    return $result;
  }
  Update._() : super();
  factory Update.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory Update.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'Update', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..e<UpdateType>(1, _omitFieldNames ? '' : 'type', $pb.PbFieldType.OE, defaultOrMaker: UpdateType.UPDATE_TYPE_UNSPECIFIED, valueOf: UpdateType.valueOf, enumValues: UpdateType.values)
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOM<Message>(3, _omitFieldNames ? '' : 'message', subBuilder: Message.create)
    ..aOS(4, _omitFieldNames ? '' : 'messageId')
    ..aOS(5, _omitFieldNames ? '' : 'userId')
    ..aOM<ReadState>(6, _omitFieldNames ? '' : 'readState', subBuilder: ReadState.create)
    ..aOM<CallSession>(7, _omitFieldNames ? '' : 'call', subBuilder: CallSession.create)
    ..aOB(8, _omitFieldNames ? '' : 'isOnline')
    ..aOB(9, _omitFieldNames ? '' : 'hasIsOnline')
    ..aOM<VerificationInfo>(10, _omitFieldNames ? '' : 'verification', subBuilder: VerificationInfo.create)
    ..aOS(11, _omitFieldNames ? '' : 'connState')
    ..aOS(12, _omitFieldNames ? '' : 'platform')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  Update clone() => Update()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  Update copyWith(void Function(Update) updates) => super.copyWith((message) => updates(message as Update)) as Update;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Update create() => Update._();
  Update createEmptyInstance() => create();
  static $pb.PbList<Update> createRepeated() => $pb.PbList<Update>();
  @$core.pragma('dart2js:noInline')
  static Update getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Update>(create);
  static Update? _defaultInstance;

  @$pb.TagNumber(1)
  UpdateType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(UpdateType v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  Message get message => $_getN(2);
  @$pb.TagNumber(3)
  set message(Message v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => clearField(3);
  @$pb.TagNumber(3)
  Message ensureMessage() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get messageId => $_getSZ(3);
  @$pb.TagNumber(4)
  set messageId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMessageId() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessageId() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get userId => $_getSZ(4);
  @$pb.TagNumber(5)
  set userId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasUserId() => $_has(4);
  @$pb.TagNumber(5)
  void clearUserId() => clearField(5);

  @$pb.TagNumber(6)
  ReadState get readState => $_getN(5);
  @$pb.TagNumber(6)
  set readState(ReadState v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasReadState() => $_has(5);
  @$pb.TagNumber(6)
  void clearReadState() => clearField(6);
  @$pb.TagNumber(6)
  ReadState ensureReadState() => $_ensure(5);

  @$pb.TagNumber(7)
  CallSession get call => $_getN(6);
  @$pb.TagNumber(7)
  set call(CallSession v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasCall() => $_has(6);
  @$pb.TagNumber(7)
  void clearCall() => clearField(7);
  @$pb.TagNumber(7)
  CallSession ensureCall() => $_ensure(6);

  @$pb.TagNumber(8)
  $core.bool get isOnline => $_getBF(7);
  @$pb.TagNumber(8)
  set isOnline($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasIsOnline() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsOnline() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get hasIsOnline_9 => $_getBF(8);
  @$pb.TagNumber(9)
  set hasIsOnline_9($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasHasIsOnline_9() => $_has(8);
  @$pb.TagNumber(9)
  void clearHasIsOnline_9() => clearField(9);

  @$pb.TagNumber(10)
  VerificationInfo get verification => $_getN(9);
  @$pb.TagNumber(10)
  set verification(VerificationInfo v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasVerification() => $_has(9);
  @$pb.TagNumber(10)
  void clearVerification() => clearField(10);
  @$pb.TagNumber(10)
  VerificationInfo ensureVerification() => $_ensure(9);

  @$pb.TagNumber(11)
  $core.String get connState => $_getSZ(10);
  @$pb.TagNumber(11)
  set connState($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasConnState() => $_has(10);
  @$pb.TagNumber(11)
  void clearConnState() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get platform => $_getSZ(11);
  @$pb.TagNumber(12)
  set platform($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasPlatform() => $_has(11);
  @$pb.TagNumber(12)
  void clearPlatform() => clearField(12);
}

class BridgeRequest extends $pb.GeneratedMessage {
  factory BridgeRequest({
    $core.String? coreId,
    $core.String? method,
    $core.List<$core.int>? payload,
  }) {
    final $result = create();
    if (coreId != null) {
      $result.coreId = coreId;
    }
    if (method != null) {
      $result.method = method;
    }
    if (payload != null) {
      $result.payload = payload;
    }
    return $result;
  }
  BridgeRequest._() : super();
  factory BridgeRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BridgeRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BridgeRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'coreId')
    ..aOS(2, _omitFieldNames ? '' : 'method')
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BridgeRequest clone() => BridgeRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BridgeRequest copyWith(void Function(BridgeRequest) updates) => super.copyWith((message) => updates(message as BridgeRequest)) as BridgeRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BridgeRequest create() => BridgeRequest._();
  BridgeRequest createEmptyInstance() => create();
  static $pb.PbList<BridgeRequest> createRepeated() => $pb.PbList<BridgeRequest>();
  @$core.pragma('dart2js:noInline')
  static BridgeRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BridgeRequest>(create);
  static BridgeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get coreId => $_getSZ(0);
  @$pb.TagNumber(1)
  set coreId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCoreId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCoreId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get method => $_getSZ(1);
  @$pb.TagNumber(2)
  set method($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMethod() => $_has(1);
  @$pb.TagNumber(2)
  void clearMethod() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get payload => $_getN(2);
  @$pb.TagNumber(3)
  set payload($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPayload() => $_has(2);
  @$pb.TagNumber(3)
  void clearPayload() => clearField(3);
}

class BridgeResponse extends $pb.GeneratedMessage {
  factory BridgeResponse({
    $core.bool? ok,
    $core.String? error,
    $core.String? errorCode,
    $core.List<$core.int>? payload,
  }) {
    final $result = create();
    if (ok != null) {
      $result.ok = ok;
    }
    if (error != null) {
      $result.error = error;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    if (payload != null) {
      $result.payload = payload;
    }
    return $result;
  }
  BridgeResponse._() : super();
  factory BridgeResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BridgeResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BridgeResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ok')
    ..aOS(2, _omitFieldNames ? '' : 'error')
    ..aOS(3, _omitFieldNames ? '' : 'errorCode')
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BridgeResponse clone() => BridgeResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BridgeResponse copyWith(void Function(BridgeResponse) updates) => super.copyWith((message) => updates(message as BridgeResponse)) as BridgeResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BridgeResponse create() => BridgeResponse._();
  BridgeResponse createEmptyInstance() => create();
  static $pb.PbList<BridgeResponse> createRepeated() => $pb.PbList<BridgeResponse>();
  @$core.pragma('dart2js:noInline')
  static BridgeResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BridgeResponse>(create);
  static BridgeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ok => $_getBF(0);
  @$pb.TagNumber(1)
  set ok($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOk() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get error => $_getSZ(1);
  @$pb.TagNumber(2)
  set error($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasError() => $_has(1);
  @$pb.TagNumber(2)
  void clearError() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get errorCode => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorCode($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasErrorCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorCode() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get payload => $_getN(3);
  @$pb.TagNumber(4)
  set payload($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPayload() => $_has(3);
  @$pb.TagNumber(4)
  void clearPayload() => clearField(4);
}

/// Event from Go → Dart (async updates)
class BridgeEvent extends $pb.GeneratedMessage {
  factory BridgeEvent({
    $core.String? coreId,
    Update? update,
    $core.List<$core.int>? engineEvent,
  }) {
    final $result = create();
    if (coreId != null) {
      $result.coreId = coreId;
    }
    if (update != null) {
      $result.update = update;
    }
    if (engineEvent != null) {
      $result.engineEvent = engineEvent;
    }
    return $result;
  }
  BridgeEvent._() : super();
  factory BridgeEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory BridgeEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'BridgeEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'coreId')
    ..aOM<Update>(2, _omitFieldNames ? '' : 'update', subBuilder: Update.create)
    ..a<$core.List<$core.int>>(3, _omitFieldNames ? '' : 'engineEvent', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  BridgeEvent clone() => BridgeEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  BridgeEvent copyWith(void Function(BridgeEvent) updates) => super.copyWith((message) => updates(message as BridgeEvent)) as BridgeEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static BridgeEvent create() => BridgeEvent._();
  BridgeEvent createEmptyInstance() => create();
  static $pb.PbList<BridgeEvent> createRepeated() => $pb.PbList<BridgeEvent>();
  @$core.pragma('dart2js:noInline')
  static BridgeEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<BridgeEvent>(create);
  static BridgeEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get coreId => $_getSZ(0);
  @$pb.TagNumber(1)
  set coreId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCoreId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCoreId() => clearField(1);

  @$pb.TagNumber(2)
  Update get update => $_getN(1);
  @$pb.TagNumber(2)
  set update(Update v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasUpdate() => $_has(1);
  @$pb.TagNumber(2)
  void clearUpdate() => clearField(2);
  @$pb.TagNumber(2)
  Update ensureUpdate() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.List<$core.int> get engineEvent => $_getN(2);
  @$pb.TagNumber(3)
  set engineEvent($core.List<$core.int> v) { $_setBytes(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasEngineEvent() => $_has(2);
  @$pb.TagNumber(3)
  void clearEngineEvent() => clearField(3);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');

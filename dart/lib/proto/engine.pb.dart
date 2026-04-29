//
//  Generated code. Do not modify.
//  source: engine.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

class EngineEvent extends $pb.GeneratedMessage {
  factory EngineEvent({
    $core.String? type,
    $core.String? accountId,
    $fixnum.Int64? timestampMs,
    $core.List<$core.int>? dataJson,
  }) {
    final $result = create();
    if (type != null) {
      $result.type = type;
    }
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (dataJson != null) {
      $result.dataJson = dataJson;
    }
    return $result;
  }
  EngineEvent._() : super();
  factory EngineEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'type')
    ..aOS(2, _omitFieldNames ? '' : 'accountId')
    ..aInt64(3, _omitFieldNames ? '' : 'timestampMs')
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'dataJson', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineEvent clone() => EngineEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineEvent copyWith(void Function(EngineEvent) updates) => super.copyWith((message) => updates(message as EngineEvent)) as EngineEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineEvent create() => EngineEvent._();
  EngineEvent createEmptyInstance() => create();
  static $pb.PbList<EngineEvent> createRepeated() => $pb.PbList<EngineEvent>();
  @$core.pragma('dart2js:noInline')
  static EngineEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineEvent>(create);
  static EngineEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get type => $_getSZ(0);
  @$pb.TagNumber(1)
  set type($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get accountId => $_getSZ(1);
  @$pb.TagNumber(2)
  set accountId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccountId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get timestampMs => $_getI64(2);
  @$pb.TagNumber(3)
  set timestampMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTimestampMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearTimestampMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get dataJson => $_getN(3);
  @$pb.TagNumber(4)
  set dataJson($core.List<$core.int> v) { $_setBytes(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDataJson() => $_has(3);
  @$pb.TagNumber(4)
  void clearDataJson() => clearField(4);
}

class AccountInfo extends $pb.GeneratedMessage {
  factory AccountInfo({
    $core.String? id,
    $core.String? platform,
    $core.String? displayName,
    $core.String? avatarPath,
    $core.int? sortOrder,
    $core.int? connState,
    $core.bool? isVerified,
    $core.bool? isPremium,
    $core.String? phone,
    $core.String? username,
    $core.String? selfUserId,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (avatarPath != null) {
      $result.avatarPath = avatarPath;
    }
    if (sortOrder != null) {
      $result.sortOrder = sortOrder;
    }
    if (connState != null) {
      $result.connState = connState;
    }
    if (isVerified != null) {
      $result.isVerified = isVerified;
    }
    if (isPremium != null) {
      $result.isPremium = isPremium;
    }
    if (phone != null) {
      $result.phone = phone;
    }
    if (username != null) {
      $result.username = username;
    }
    if (selfUserId != null) {
      $result.selfUserId = selfUserId;
    }
    return $result;
  }
  AccountInfo._() : super();
  factory AccountInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AccountInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AccountInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'platform')
    ..aOS(3, _omitFieldNames ? '' : 'displayName')
    ..aOS(4, _omitFieldNames ? '' : 'avatarPath')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'sortOrder', $pb.PbFieldType.O3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'connState', $pb.PbFieldType.O3)
    ..aOB(7, _omitFieldNames ? '' : 'isVerified')
    ..aOB(8, _omitFieldNames ? '' : 'isPremium')
    ..aOS(9, _omitFieldNames ? '' : 'phone')
    ..aOS(10, _omitFieldNames ? '' : 'username')
    ..aOS(11, _omitFieldNames ? '' : 'selfUserId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AccountInfo clone() => AccountInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AccountInfo copyWith(void Function(AccountInfo) updates) => super.copyWith((message) => updates(message as AccountInfo)) as AccountInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AccountInfo create() => AccountInfo._();
  AccountInfo createEmptyInstance() => create();
  static $pb.PbList<AccountInfo> createRepeated() => $pb.PbList<AccountInfo>();
  @$core.pragma('dart2js:noInline')
  static AccountInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AccountInfo>(create);
  static AccountInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get platform => $_getSZ(1);
  @$pb.TagNumber(2)
  set platform($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPlatform() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlatform() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get displayName => $_getSZ(2);
  @$pb.TagNumber(3)
  set displayName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDisplayName() => $_has(2);
  @$pb.TagNumber(3)
  void clearDisplayName() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get avatarPath => $_getSZ(3);
  @$pb.TagNumber(4)
  set avatarPath($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAvatarPath() => $_has(3);
  @$pb.TagNumber(4)
  void clearAvatarPath() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get sortOrder => $_getIZ(4);
  @$pb.TagNumber(5)
  set sortOrder($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSortOrder() => $_has(4);
  @$pb.TagNumber(5)
  void clearSortOrder() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get connState => $_getIZ(5);
  @$pb.TagNumber(6)
  set connState($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasConnState() => $_has(5);
  @$pb.TagNumber(6)
  void clearConnState() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isVerified => $_getBF(6);
  @$pb.TagNumber(7)
  set isVerified($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsVerified() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsVerified() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get isPremium => $_getBF(7);
  @$pb.TagNumber(8)
  set isPremium($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasIsPremium() => $_has(7);
  @$pb.TagNumber(8)
  void clearIsPremium() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get phone => $_getSZ(8);
  @$pb.TagNumber(9)
  set phone($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasPhone() => $_has(8);
  @$pb.TagNumber(9)
  void clearPhone() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get username => $_getSZ(9);
  @$pb.TagNumber(10)
  set username($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasUsername() => $_has(9);
  @$pb.TagNumber(10)
  void clearUsername() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get selfUserId => $_getSZ(10);
  @$pb.TagNumber(11)
  set selfUserId($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasSelfUserId() => $_has(10);
  @$pb.TagNumber(11)
  void clearSelfUserId() => clearField(11);
}

class EngineInitRequest extends $pb.GeneratedMessage {
  factory EngineInitRequest({
    $core.String? configDir,
    $core.String? cacheDir,
    $core.String? downloadDir,
    $core.String? vaultPassword,
  }) {
    final $result = create();
    if (configDir != null) {
      $result.configDir = configDir;
    }
    if (cacheDir != null) {
      $result.cacheDir = cacheDir;
    }
    if (downloadDir != null) {
      $result.downloadDir = downloadDir;
    }
    if (vaultPassword != null) {
      $result.vaultPassword = vaultPassword;
    }
    return $result;
  }
  EngineInitRequest._() : super();
  factory EngineInitRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineInitRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineInitRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'configDir')
    ..aOS(2, _omitFieldNames ? '' : 'cacheDir')
    ..aOS(3, _omitFieldNames ? '' : 'downloadDir')
    ..aOS(4, _omitFieldNames ? '' : 'vaultPassword')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineInitRequest clone() => EngineInitRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineInitRequest copyWith(void Function(EngineInitRequest) updates) => super.copyWith((message) => updates(message as EngineInitRequest)) as EngineInitRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineInitRequest create() => EngineInitRequest._();
  EngineInitRequest createEmptyInstance() => create();
  static $pb.PbList<EngineInitRequest> createRepeated() => $pb.PbList<EngineInitRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineInitRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineInitRequest>(create);
  static EngineInitRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get configDir => $_getSZ(0);
  @$pb.TagNumber(1)
  set configDir($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasConfigDir() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfigDir() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get cacheDir => $_getSZ(1);
  @$pb.TagNumber(2)
  set cacheDir($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCacheDir() => $_has(1);
  @$pb.TagNumber(2)
  void clearCacheDir() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get downloadDir => $_getSZ(2);
  @$pb.TagNumber(3)
  set downloadDir($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDownloadDir() => $_has(2);
  @$pb.TagNumber(3)
  void clearDownloadDir() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get vaultPassword => $_getSZ(3);
  @$pb.TagNumber(4)
  set vaultPassword($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasVaultPassword() => $_has(3);
  @$pb.TagNumber(4)
  void clearVaultPassword() => clearField(4);
}

class EngineInitResponse extends $pb.GeneratedMessage {
  factory EngineInitResponse({
    $core.bool? ok,
    $core.String? error,
  }) {
    final $result = create();
    if (ok != null) {
      $result.ok = ok;
    }
    if (error != null) {
      $result.error = error;
    }
    return $result;
  }
  EngineInitResponse._() : super();
  factory EngineInitResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineInitResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineInitResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ok')
    ..aOS(2, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineInitResponse clone() => EngineInitResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineInitResponse copyWith(void Function(EngineInitResponse) updates) => super.copyWith((message) => updates(message as EngineInitResponse)) as EngineInitResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineInitResponse create() => EngineInitResponse._();
  EngineInitResponse createEmptyInstance() => create();
  static $pb.PbList<EngineInitResponse> createRepeated() => $pb.PbList<EngineInitResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineInitResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineInitResponse>(create);
  static EngineInitResponse? _defaultInstance;

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
}

class EngineListAccountsResponse extends $pb.GeneratedMessage {
  factory EngineListAccountsResponse({
    $core.Iterable<AccountInfo>? accounts,
  }) {
    final $result = create();
    if (accounts != null) {
      $result.accounts.addAll(accounts);
    }
    return $result;
  }
  EngineListAccountsResponse._() : super();
  factory EngineListAccountsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineListAccountsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineListAccountsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<AccountInfo>(1, _omitFieldNames ? '' : 'accounts', $pb.PbFieldType.PM, subBuilder: AccountInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineListAccountsResponse clone() => EngineListAccountsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineListAccountsResponse copyWith(void Function(EngineListAccountsResponse) updates) => super.copyWith((message) => updates(message as EngineListAccountsResponse)) as EngineListAccountsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineListAccountsResponse create() => EngineListAccountsResponse._();
  EngineListAccountsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineListAccountsResponse> createRepeated() => $pb.PbList<EngineListAccountsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineListAccountsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineListAccountsResponse>(create);
  static EngineListAccountsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<AccountInfo> get accounts => $_getList(0);
}

class EngineAddAccountRequest extends $pb.GeneratedMessage {
  factory EngineAddAccountRequest({
    $core.String? platform,
  }) {
    final $result = create();
    if (platform != null) {
      $result.platform = platform;
    }
    return $result;
  }
  EngineAddAccountRequest._() : super();
  factory EngineAddAccountRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineAddAccountRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineAddAccountRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'platform')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineAddAccountRequest clone() => EngineAddAccountRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineAddAccountRequest copyWith(void Function(EngineAddAccountRequest) updates) => super.copyWith((message) => updates(message as EngineAddAccountRequest)) as EngineAddAccountRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineAddAccountRequest create() => EngineAddAccountRequest._();
  EngineAddAccountRequest createEmptyInstance() => create();
  static $pb.PbList<EngineAddAccountRequest> createRepeated() => $pb.PbList<EngineAddAccountRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineAddAccountRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineAddAccountRequest>(create);
  static EngineAddAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get platform => $_getSZ(0);
  @$pb.TagNumber(1)
  set platform($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPlatform() => $_has(0);
  @$pb.TagNumber(1)
  void clearPlatform() => clearField(1);
}

class EngineAddAccountResponse extends $pb.GeneratedMessage {
  factory EngineAddAccountResponse({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineAddAccountResponse._() : super();
  factory EngineAddAccountResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineAddAccountResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineAddAccountResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineAddAccountResponse clone() => EngineAddAccountResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineAddAccountResponse copyWith(void Function(EngineAddAccountResponse) updates) => super.copyWith((message) => updates(message as EngineAddAccountResponse)) as EngineAddAccountResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineAddAccountResponse create() => EngineAddAccountResponse._();
  EngineAddAccountResponse createEmptyInstance() => create();
  static $pb.PbList<EngineAddAccountResponse> createRepeated() => $pb.PbList<EngineAddAccountResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineAddAccountResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineAddAccountResponse>(create);
  static EngineAddAccountResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class EngineRemoveAccountRequest extends $pb.GeneratedMessage {
  factory EngineRemoveAccountRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineRemoveAccountRequest._() : super();
  factory EngineRemoveAccountRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineRemoveAccountRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineRemoveAccountRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineRemoveAccountRequest clone() => EngineRemoveAccountRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineRemoveAccountRequest copyWith(void Function(EngineRemoveAccountRequest) updates) => super.copyWith((message) => updates(message as EngineRemoveAccountRequest)) as EngineRemoveAccountRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineRemoveAccountRequest create() => EngineRemoveAccountRequest._();
  EngineRemoveAccountRequest createEmptyInstance() => create();
  static $pb.PbList<EngineRemoveAccountRequest> createRepeated() => $pb.PbList<EngineRemoveAccountRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineRemoveAccountRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineRemoveAccountRequest>(create);
  static EngineRemoveAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class EngineReorderAccountsRequest extends $pb.GeneratedMessage {
  factory EngineReorderAccountsRequest({
    $core.Iterable<$core.String>? accountIds,
  }) {
    final $result = create();
    if (accountIds != null) {
      $result.accountIds.addAll(accountIds);
    }
    return $result;
  }
  EngineReorderAccountsRequest._() : super();
  factory EngineReorderAccountsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineReorderAccountsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineReorderAccountsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'accountIds')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineReorderAccountsRequest clone() => EngineReorderAccountsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineReorderAccountsRequest copyWith(void Function(EngineReorderAccountsRequest) updates) => super.copyWith((message) => updates(message as EngineReorderAccountsRequest)) as EngineReorderAccountsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineReorderAccountsRequest create() => EngineReorderAccountsRequest._();
  EngineReorderAccountsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineReorderAccountsRequest> createRepeated() => $pb.PbList<EngineReorderAccountsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineReorderAccountsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineReorderAccountsRequest>(create);
  static EngineReorderAccountsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.String> get accountIds => $_getList(0);
}

class EngineConnectAccountRequest extends $pb.GeneratedMessage {
  factory EngineConnectAccountRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineConnectAccountRequest._() : super();
  factory EngineConnectAccountRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineConnectAccountRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineConnectAccountRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineConnectAccountRequest clone() => EngineConnectAccountRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineConnectAccountRequest copyWith(void Function(EngineConnectAccountRequest) updates) => super.copyWith((message) => updates(message as EngineConnectAccountRequest)) as EngineConnectAccountRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineConnectAccountRequest create() => EngineConnectAccountRequest._();
  EngineConnectAccountRequest createEmptyInstance() => create();
  static $pb.PbList<EngineConnectAccountRequest> createRepeated() => $pb.PbList<EngineConnectAccountRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineConnectAccountRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineConnectAccountRequest>(create);
  static EngineConnectAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class EngineDisconnectAccountRequest extends $pb.GeneratedMessage {
  factory EngineDisconnectAccountRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineDisconnectAccountRequest._() : super();
  factory EngineDisconnectAccountRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineDisconnectAccountRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineDisconnectAccountRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineDisconnectAccountRequest clone() => EngineDisconnectAccountRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineDisconnectAccountRequest copyWith(void Function(EngineDisconnectAccountRequest) updates) => super.copyWith((message) => updates(message as EngineDisconnectAccountRequest)) as EngineDisconnectAccountRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineDisconnectAccountRequest create() => EngineDisconnectAccountRequest._();
  EngineDisconnectAccountRequest createEmptyInstance() => create();
  static $pb.PbList<EngineDisconnectAccountRequest> createRepeated() => $pb.PbList<EngineDisconnectAccountRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineDisconnectAccountRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineDisconnectAccountRequest>(create);
  static EngineDisconnectAccountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class AuthOption extends $pb.GeneratedMessage {
  factory AuthOption({
    $core.String? id,
    $core.String? label,
  }) {
    final $result = create();
    if (id != null) {
      $result.id = id;
    }
    if (label != null) {
      $result.label = label;
    }
    return $result;
  }
  AuthOption._() : super();
  factory AuthOption.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AuthOption.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AuthOption', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'label')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AuthOption clone() => AuthOption()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AuthOption copyWith(void Function(AuthOption) updates) => super.copyWith((message) => updates(message as AuthOption)) as AuthOption;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuthOption create() => AuthOption._();
  AuthOption createEmptyInstance() => create();
  static $pb.PbList<AuthOption> createRepeated() => $pb.PbList<AuthOption>();
  @$core.pragma('dart2js:noInline')
  static AuthOption getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AuthOption>(create);
  static AuthOption? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get label => $_getSZ(1);
  @$pb.TagNumber(2)
  set label($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLabel() => $_has(1);
  @$pb.TagNumber(2)
  void clearLabel() => clearField(2);
}

class EngineAuthState extends $pb.GeneratedMessage {
  factory EngineAuthState({
    $core.String? accountId,
    $core.String? platform,
    $core.String? state,
    $core.Iterable<AuthOption>? options,
    $core.String? fieldType,
    $core.String? label,
    $core.String? hint,
    $core.String? error,
    $core.int? codeLength,
    $core.String? sentTo,
    $core.int? timeoutSecs,
    $core.bool? canResend,
    $core.bool? hasRecovery,
    $core.List<$core.int>? qrData,
    $core.int? qrExpiresIn,
    $core.String? displayName,
    $core.String? avatarB64,
    $core.String? message,
    $core.bool? recoverable,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (platform != null) {
      $result.platform = platform;
    }
    if (state != null) {
      $result.state = state;
    }
    if (options != null) {
      $result.options.addAll(options);
    }
    if (fieldType != null) {
      $result.fieldType = fieldType;
    }
    if (label != null) {
      $result.label = label;
    }
    if (hint != null) {
      $result.hint = hint;
    }
    if (error != null) {
      $result.error = error;
    }
    if (codeLength != null) {
      $result.codeLength = codeLength;
    }
    if (sentTo != null) {
      $result.sentTo = sentTo;
    }
    if (timeoutSecs != null) {
      $result.timeoutSecs = timeoutSecs;
    }
    if (canResend != null) {
      $result.canResend = canResend;
    }
    if (hasRecovery != null) {
      $result.hasRecovery = hasRecovery;
    }
    if (qrData != null) {
      $result.qrData = qrData;
    }
    if (qrExpiresIn != null) {
      $result.qrExpiresIn = qrExpiresIn;
    }
    if (displayName != null) {
      $result.displayName = displayName;
    }
    if (avatarB64 != null) {
      $result.avatarB64 = avatarB64;
    }
    if (message != null) {
      $result.message = message;
    }
    if (recoverable != null) {
      $result.recoverable = recoverable;
    }
    return $result;
  }
  EngineAuthState._() : super();
  factory EngineAuthState.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineAuthState.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineAuthState', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'platform')
    ..aOS(3, _omitFieldNames ? '' : 'state')
    ..pc<AuthOption>(10, _omitFieldNames ? '' : 'options', $pb.PbFieldType.PM, subBuilder: AuthOption.create)
    ..aOS(11, _omitFieldNames ? '' : 'fieldType')
    ..aOS(12, _omitFieldNames ? '' : 'label')
    ..aOS(13, _omitFieldNames ? '' : 'hint')
    ..aOS(14, _omitFieldNames ? '' : 'error')
    ..a<$core.int>(15, _omitFieldNames ? '' : 'codeLength', $pb.PbFieldType.O3)
    ..aOS(16, _omitFieldNames ? '' : 'sentTo')
    ..a<$core.int>(17, _omitFieldNames ? '' : 'timeoutSecs', $pb.PbFieldType.O3)
    ..aOB(18, _omitFieldNames ? '' : 'canResend')
    ..aOB(19, _omitFieldNames ? '' : 'hasRecovery')
    ..a<$core.List<$core.int>>(20, _omitFieldNames ? '' : 'qrData', $pb.PbFieldType.OY)
    ..a<$core.int>(21, _omitFieldNames ? '' : 'qrExpiresIn', $pb.PbFieldType.O3)
    ..aOS(22, _omitFieldNames ? '' : 'displayName')
    ..aOS(23, _omitFieldNames ? '' : 'avatarB64')
    ..aOS(24, _omitFieldNames ? '' : 'message')
    ..aOB(25, _omitFieldNames ? '' : 'recoverable')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineAuthState clone() => EngineAuthState()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineAuthState copyWith(void Function(EngineAuthState) updates) => super.copyWith((message) => updates(message as EngineAuthState)) as EngineAuthState;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineAuthState create() => EngineAuthState._();
  EngineAuthState createEmptyInstance() => create();
  static $pb.PbList<EngineAuthState> createRepeated() => $pb.PbList<EngineAuthState>();
  @$core.pragma('dart2js:noInline')
  static EngineAuthState getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineAuthState>(create);
  static EngineAuthState? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get platform => $_getSZ(1);
  @$pb.TagNumber(2)
  set platform($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPlatform() => $_has(1);
  @$pb.TagNumber(2)
  void clearPlatform() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get state => $_getSZ(2);
  @$pb.TagNumber(3)
  set state($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasState() => $_has(2);
  @$pb.TagNumber(3)
  void clearState() => clearField(3);

  @$pb.TagNumber(10)
  $core.List<AuthOption> get options => $_getList(3);

  @$pb.TagNumber(11)
  $core.String get fieldType => $_getSZ(4);
  @$pb.TagNumber(11)
  set fieldType($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(11)
  $core.bool hasFieldType() => $_has(4);
  @$pb.TagNumber(11)
  void clearFieldType() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get label => $_getSZ(5);
  @$pb.TagNumber(12)
  set label($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(12)
  $core.bool hasLabel() => $_has(5);
  @$pb.TagNumber(12)
  void clearLabel() => clearField(12);

  @$pb.TagNumber(13)
  $core.String get hint => $_getSZ(6);
  @$pb.TagNumber(13)
  set hint($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(13)
  $core.bool hasHint() => $_has(6);
  @$pb.TagNumber(13)
  void clearHint() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get error => $_getSZ(7);
  @$pb.TagNumber(14)
  set error($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(14)
  $core.bool hasError() => $_has(7);
  @$pb.TagNumber(14)
  void clearError() => clearField(14);

  @$pb.TagNumber(15)
  $core.int get codeLength => $_getIZ(8);
  @$pb.TagNumber(15)
  set codeLength($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(15)
  $core.bool hasCodeLength() => $_has(8);
  @$pb.TagNumber(15)
  void clearCodeLength() => clearField(15);

  @$pb.TagNumber(16)
  $core.String get sentTo => $_getSZ(9);
  @$pb.TagNumber(16)
  set sentTo($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(16)
  $core.bool hasSentTo() => $_has(9);
  @$pb.TagNumber(16)
  void clearSentTo() => clearField(16);

  @$pb.TagNumber(17)
  $core.int get timeoutSecs => $_getIZ(10);
  @$pb.TagNumber(17)
  set timeoutSecs($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(17)
  $core.bool hasTimeoutSecs() => $_has(10);
  @$pb.TagNumber(17)
  void clearTimeoutSecs() => clearField(17);

  @$pb.TagNumber(18)
  $core.bool get canResend => $_getBF(11);
  @$pb.TagNumber(18)
  set canResend($core.bool v) { $_setBool(11, v); }
  @$pb.TagNumber(18)
  $core.bool hasCanResend() => $_has(11);
  @$pb.TagNumber(18)
  void clearCanResend() => clearField(18);

  @$pb.TagNumber(19)
  $core.bool get hasRecovery => $_getBF(12);
  @$pb.TagNumber(19)
  set hasRecovery($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(19)
  $core.bool hasHasRecovery() => $_has(12);
  @$pb.TagNumber(19)
  void clearHasRecovery() => clearField(19);

  @$pb.TagNumber(20)
  $core.List<$core.int> get qrData => $_getN(13);
  @$pb.TagNumber(20)
  set qrData($core.List<$core.int> v) { $_setBytes(13, v); }
  @$pb.TagNumber(20)
  $core.bool hasQrData() => $_has(13);
  @$pb.TagNumber(20)
  void clearQrData() => clearField(20);

  @$pb.TagNumber(21)
  $core.int get qrExpiresIn => $_getIZ(14);
  @$pb.TagNumber(21)
  set qrExpiresIn($core.int v) { $_setSignedInt32(14, v); }
  @$pb.TagNumber(21)
  $core.bool hasQrExpiresIn() => $_has(14);
  @$pb.TagNumber(21)
  void clearQrExpiresIn() => clearField(21);

  @$pb.TagNumber(22)
  $core.String get displayName => $_getSZ(15);
  @$pb.TagNumber(22)
  set displayName($core.String v) { $_setString(15, v); }
  @$pb.TagNumber(22)
  $core.bool hasDisplayName() => $_has(15);
  @$pb.TagNumber(22)
  void clearDisplayName() => clearField(22);

  @$pb.TagNumber(23)
  $core.String get avatarB64 => $_getSZ(16);
  @$pb.TagNumber(23)
  set avatarB64($core.String v) { $_setString(16, v); }
  @$pb.TagNumber(23)
  $core.bool hasAvatarB64() => $_has(16);
  @$pb.TagNumber(23)
  void clearAvatarB64() => clearField(23);

  @$pb.TagNumber(24)
  $core.String get message => $_getSZ(17);
  @$pb.TagNumber(24)
  set message($core.String v) { $_setString(17, v); }
  @$pb.TagNumber(24)
  $core.bool hasMessage() => $_has(17);
  @$pb.TagNumber(24)
  void clearMessage() => clearField(24);

  @$pb.TagNumber(25)
  $core.bool get recoverable => $_getBF(18);
  @$pb.TagNumber(25)
  set recoverable($core.bool v) { $_setBool(18, v); }
  @$pb.TagNumber(25)
  $core.bool hasRecoverable() => $_has(18);
  @$pb.TagNumber(25)
  void clearRecoverable() => clearField(25);
}

class EngineStartAuthRequest extends $pb.GeneratedMessage {
  factory EngineStartAuthRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineStartAuthRequest._() : super();
  factory EngineStartAuthRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineStartAuthRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineStartAuthRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineStartAuthRequest clone() => EngineStartAuthRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineStartAuthRequest copyWith(void Function(EngineStartAuthRequest) updates) => super.copyWith((message) => updates(message as EngineStartAuthRequest)) as EngineStartAuthRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineStartAuthRequest create() => EngineStartAuthRequest._();
  EngineStartAuthRequest createEmptyInstance() => create();
  static $pb.PbList<EngineStartAuthRequest> createRepeated() => $pb.PbList<EngineStartAuthRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineStartAuthRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineStartAuthRequest>(create);
  static EngineStartAuthRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class EngineStartAuthResponse extends $pb.GeneratedMessage {
  factory EngineStartAuthResponse({
    EngineAuthState? state,
  }) {
    final $result = create();
    if (state != null) {
      $result.state = state;
    }
    return $result;
  }
  EngineStartAuthResponse._() : super();
  factory EngineStartAuthResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineStartAuthResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineStartAuthResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOM<EngineAuthState>(1, _omitFieldNames ? '' : 'state', subBuilder: EngineAuthState.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineStartAuthResponse clone() => EngineStartAuthResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineStartAuthResponse copyWith(void Function(EngineStartAuthResponse) updates) => super.copyWith((message) => updates(message as EngineStartAuthResponse)) as EngineStartAuthResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineStartAuthResponse create() => EngineStartAuthResponse._();
  EngineStartAuthResponse createEmptyInstance() => create();
  static $pb.PbList<EngineStartAuthResponse> createRepeated() => $pb.PbList<EngineStartAuthResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineStartAuthResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineStartAuthResponse>(create);
  static EngineStartAuthResponse? _defaultInstance;

  @$pb.TagNumber(1)
  EngineAuthState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(EngineAuthState v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => clearField(1);
  @$pb.TagNumber(1)
  EngineAuthState ensureState() => $_ensure(0);
}

class EngineSubmitAuthInputRequest extends $pb.GeneratedMessage {
  factory EngineSubmitAuthInputRequest({
    $core.String? accountId,
    $core.String? input,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (input != null) {
      $result.input = input;
    }
    return $result;
  }
  EngineSubmitAuthInputRequest._() : super();
  factory EngineSubmitAuthInputRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSubmitAuthInputRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSubmitAuthInputRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'input')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSubmitAuthInputRequest clone() => EngineSubmitAuthInputRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSubmitAuthInputRequest copyWith(void Function(EngineSubmitAuthInputRequest) updates) => super.copyWith((message) => updates(message as EngineSubmitAuthInputRequest)) as EngineSubmitAuthInputRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSubmitAuthInputRequest create() => EngineSubmitAuthInputRequest._();
  EngineSubmitAuthInputRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSubmitAuthInputRequest> createRepeated() => $pb.PbList<EngineSubmitAuthInputRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSubmitAuthInputRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSubmitAuthInputRequest>(create);
  static EngineSubmitAuthInputRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get input => $_getSZ(1);
  @$pb.TagNumber(2)
  set input($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasInput() => $_has(1);
  @$pb.TagNumber(2)
  void clearInput() => clearField(2);
}

class EngineSubmitAuthInputResponse extends $pb.GeneratedMessage {
  factory EngineSubmitAuthInputResponse({
    EngineAuthState? state,
  }) {
    final $result = create();
    if (state != null) {
      $result.state = state;
    }
    return $result;
  }
  EngineSubmitAuthInputResponse._() : super();
  factory EngineSubmitAuthInputResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSubmitAuthInputResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSubmitAuthInputResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOM<EngineAuthState>(1, _omitFieldNames ? '' : 'state', subBuilder: EngineAuthState.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSubmitAuthInputResponse clone() => EngineSubmitAuthInputResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSubmitAuthInputResponse copyWith(void Function(EngineSubmitAuthInputResponse) updates) => super.copyWith((message) => updates(message as EngineSubmitAuthInputResponse)) as EngineSubmitAuthInputResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSubmitAuthInputResponse create() => EngineSubmitAuthInputResponse._();
  EngineSubmitAuthInputResponse createEmptyInstance() => create();
  static $pb.PbList<EngineSubmitAuthInputResponse> createRepeated() => $pb.PbList<EngineSubmitAuthInputResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineSubmitAuthInputResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSubmitAuthInputResponse>(create);
  static EngineSubmitAuthInputResponse? _defaultInstance;

  @$pb.TagNumber(1)
  EngineAuthState get state => $_getN(0);
  @$pb.TagNumber(1)
  set state(EngineAuthState v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasState() => $_has(0);
  @$pb.TagNumber(1)
  void clearState() => clearField(1);
  @$pb.TagNumber(1)
  EngineAuthState ensureState() => $_ensure(0);
}

class EngineCancelAuthRequest extends $pb.GeneratedMessage {
  factory EngineCancelAuthRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineCancelAuthRequest._() : super();
  factory EngineCancelAuthRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineCancelAuthRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCancelAuthRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineCancelAuthRequest clone() => EngineCancelAuthRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineCancelAuthRequest copyWith(void Function(EngineCancelAuthRequest) updates) => super.copyWith((message) => updates(message as EngineCancelAuthRequest)) as EngineCancelAuthRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineCancelAuthRequest create() => EngineCancelAuthRequest._();
  EngineCancelAuthRequest createEmptyInstance() => create();
  static $pb.PbList<EngineCancelAuthRequest> createRepeated() => $pb.PbList<EngineCancelAuthRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineCancelAuthRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCancelAuthRequest>(create);
  static EngineCancelAuthRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class EngineChatInfo extends $pb.GeneratedMessage {
  factory EngineChatInfo({
    $core.String? accountId,
    $core.String? chatId,
    $core.int? type,
    $core.String? title,
    $core.String? avatarPath,
    $core.String? lastMsgId,
    $core.String? lastMsgText,
    $fixnum.Int64? lastMsgTime,
    $core.String? lastMsgSender,
    $core.int? unreadCount,
    $core.bool? isMuted,
    $core.bool? isPinned,
    $core.bool? isArchived,
    $core.String? draftText,
    $core.int? memberCount,
    $core.String? parentId,
    $core.bool? lastMsgIsOutgoing,
    $core.bool? isBot,
    $core.int? lastMsgStatus,
    $core.bool? isContact,
    $core.bool? isBlocked,
    $core.int? slowmodeSeconds,
    $fixnum.Int64? slowmodeNextSendDate,
    $core.int? starsToSend,
    $core.int? ttlPeriod,
    $core.String? emojiStatusId,
    $core.bool? isForum,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (type != null) {
      $result.type = type;
    }
    if (title != null) {
      $result.title = title;
    }
    if (avatarPath != null) {
      $result.avatarPath = avatarPath;
    }
    if (lastMsgId != null) {
      $result.lastMsgId = lastMsgId;
    }
    if (lastMsgText != null) {
      $result.lastMsgText = lastMsgText;
    }
    if (lastMsgTime != null) {
      $result.lastMsgTime = lastMsgTime;
    }
    if (lastMsgSender != null) {
      $result.lastMsgSender = lastMsgSender;
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
    if (draftText != null) {
      $result.draftText = draftText;
    }
    if (memberCount != null) {
      $result.memberCount = memberCount;
    }
    if (parentId != null) {
      $result.parentId = parentId;
    }
    if (lastMsgIsOutgoing != null) {
      $result.lastMsgIsOutgoing = lastMsgIsOutgoing;
    }
    if (isBot != null) {
      $result.isBot = isBot;
    }
    if (lastMsgStatus != null) {
      $result.lastMsgStatus = lastMsgStatus;
    }
    if (isContact != null) {
      $result.isContact = isContact;
    }
    if (isBlocked != null) {
      $result.isBlocked = isBlocked;
    }
    if (slowmodeSeconds != null) {
      $result.slowmodeSeconds = slowmodeSeconds;
    }
    if (slowmodeNextSendDate != null) {
      $result.slowmodeNextSendDate = slowmodeNextSendDate;
    }
    if (starsToSend != null) {
      $result.starsToSend = starsToSend;
    }
    if (ttlPeriod != null) {
      $result.ttlPeriod = ttlPeriod;
    }
    if (emojiStatusId != null) {
      $result.emojiStatusId = emojiStatusId;
    }
    if (isForum != null) {
      $result.isForum = isForum;
    }
    return $result;
  }
  EngineChatInfo._() : super();
  factory EngineChatInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineChatInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineChatInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'type', $pb.PbFieldType.O3)
    ..aOS(4, _omitFieldNames ? '' : 'title')
    ..aOS(5, _omitFieldNames ? '' : 'avatarPath')
    ..aOS(6, _omitFieldNames ? '' : 'lastMsgId')
    ..aOS(7, _omitFieldNames ? '' : 'lastMsgText')
    ..aInt64(8, _omitFieldNames ? '' : 'lastMsgTime')
    ..aOS(9, _omitFieldNames ? '' : 'lastMsgSender')
    ..a<$core.int>(10, _omitFieldNames ? '' : 'unreadCount', $pb.PbFieldType.O3)
    ..aOB(11, _omitFieldNames ? '' : 'isMuted')
    ..aOB(12, _omitFieldNames ? '' : 'isPinned')
    ..aOB(13, _omitFieldNames ? '' : 'isArchived')
    ..aOS(14, _omitFieldNames ? '' : 'draftText')
    ..a<$core.int>(15, _omitFieldNames ? '' : 'memberCount', $pb.PbFieldType.O3)
    ..aOS(16, _omitFieldNames ? '' : 'parentId')
    ..aOB(17, _omitFieldNames ? '' : 'lastMsgIsOutgoing')
    ..aOB(18, _omitFieldNames ? '' : 'isBot')
    ..a<$core.int>(19, _omitFieldNames ? '' : 'lastMsgStatus', $pb.PbFieldType.O3)
    ..aOB(20, _omitFieldNames ? '' : 'isContact')
    ..aOB(21, _omitFieldNames ? '' : 'isBlocked')
    ..a<$core.int>(22, _omitFieldNames ? '' : 'slowmodeSeconds', $pb.PbFieldType.O3)
    ..aInt64(23, _omitFieldNames ? '' : 'slowmodeNextSendDate')
    ..a<$core.int>(24, _omitFieldNames ? '' : 'starsToSend', $pb.PbFieldType.O3)
    ..a<$core.int>(25, _omitFieldNames ? '' : 'ttlPeriod', $pb.PbFieldType.O3)
    ..aOS(26, _omitFieldNames ? '' : 'emojiStatusId')
    ..aOB(27, _omitFieldNames ? '' : 'isForum')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineChatInfo clone() => EngineChatInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineChatInfo copyWith(void Function(EngineChatInfo) updates) => super.copyWith((message) => updates(message as EngineChatInfo)) as EngineChatInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineChatInfo create() => EngineChatInfo._();
  EngineChatInfo createEmptyInstance() => create();
  static $pb.PbList<EngineChatInfo> createRepeated() => $pb.PbList<EngineChatInfo>();
  @$core.pragma('dart2js:noInline')
  static EngineChatInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineChatInfo>(create);
  static EngineChatInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get type => $_getIZ(2);
  @$pb.TagNumber(3)
  set type($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasType() => $_has(2);
  @$pb.TagNumber(3)
  void clearType() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get title => $_getSZ(3);
  @$pb.TagNumber(4)
  set title($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTitle() => $_has(3);
  @$pb.TagNumber(4)
  void clearTitle() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get avatarPath => $_getSZ(4);
  @$pb.TagNumber(5)
  set avatarPath($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAvatarPath() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvatarPath() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get lastMsgId => $_getSZ(5);
  @$pb.TagNumber(6)
  set lastMsgId($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasLastMsgId() => $_has(5);
  @$pb.TagNumber(6)
  void clearLastMsgId() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get lastMsgText => $_getSZ(6);
  @$pb.TagNumber(7)
  set lastMsgText($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasLastMsgText() => $_has(6);
  @$pb.TagNumber(7)
  void clearLastMsgText() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get lastMsgTime => $_getI64(7);
  @$pb.TagNumber(8)
  set lastMsgTime($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasLastMsgTime() => $_has(7);
  @$pb.TagNumber(8)
  void clearLastMsgTime() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get lastMsgSender => $_getSZ(8);
  @$pb.TagNumber(9)
  set lastMsgSender($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasLastMsgSender() => $_has(8);
  @$pb.TagNumber(9)
  void clearLastMsgSender() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get unreadCount => $_getIZ(9);
  @$pb.TagNumber(10)
  set unreadCount($core.int v) { $_setSignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasUnreadCount() => $_has(9);
  @$pb.TagNumber(10)
  void clearUnreadCount() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get isMuted => $_getBF(10);
  @$pb.TagNumber(11)
  set isMuted($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasIsMuted() => $_has(10);
  @$pb.TagNumber(11)
  void clearIsMuted() => clearField(11);

  @$pb.TagNumber(12)
  $core.bool get isPinned => $_getBF(11);
  @$pb.TagNumber(12)
  set isPinned($core.bool v) { $_setBool(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasIsPinned() => $_has(11);
  @$pb.TagNumber(12)
  void clearIsPinned() => clearField(12);

  @$pb.TagNumber(13)
  $core.bool get isArchived => $_getBF(12);
  @$pb.TagNumber(13)
  set isArchived($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasIsArchived() => $_has(12);
  @$pb.TagNumber(13)
  void clearIsArchived() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get draftText => $_getSZ(13);
  @$pb.TagNumber(14)
  set draftText($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasDraftText() => $_has(13);
  @$pb.TagNumber(14)
  void clearDraftText() => clearField(14);

  @$pb.TagNumber(15)
  $core.int get memberCount => $_getIZ(14);
  @$pb.TagNumber(15)
  set memberCount($core.int v) { $_setSignedInt32(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasMemberCount() => $_has(14);
  @$pb.TagNumber(15)
  void clearMemberCount() => clearField(15);

  @$pb.TagNumber(16)
  $core.String get parentId => $_getSZ(15);
  @$pb.TagNumber(16)
  set parentId($core.String v) { $_setString(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasParentId() => $_has(15);
  @$pb.TagNumber(16)
  void clearParentId() => clearField(16);

  @$pb.TagNumber(17)
  $core.bool get lastMsgIsOutgoing => $_getBF(16);
  @$pb.TagNumber(17)
  set lastMsgIsOutgoing($core.bool v) { $_setBool(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasLastMsgIsOutgoing() => $_has(16);
  @$pb.TagNumber(17)
  void clearLastMsgIsOutgoing() => clearField(17);

  @$pb.TagNumber(18)
  $core.bool get isBot => $_getBF(17);
  @$pb.TagNumber(18)
  set isBot($core.bool v) { $_setBool(17, v); }
  @$pb.TagNumber(18)
  $core.bool hasIsBot() => $_has(17);
  @$pb.TagNumber(18)
  void clearIsBot() => clearField(18);

  @$pb.TagNumber(19)
  $core.int get lastMsgStatus => $_getIZ(18);
  @$pb.TagNumber(19)
  set lastMsgStatus($core.int v) { $_setSignedInt32(18, v); }
  @$pb.TagNumber(19)
  $core.bool hasLastMsgStatus() => $_has(18);
  @$pb.TagNumber(19)
  void clearLastMsgStatus() => clearField(19);

  @$pb.TagNumber(20)
  $core.bool get isContact => $_getBF(19);
  @$pb.TagNumber(20)
  set isContact($core.bool v) { $_setBool(19, v); }
  @$pb.TagNumber(20)
  $core.bool hasIsContact() => $_has(19);
  @$pb.TagNumber(20)
  void clearIsContact() => clearField(20);

  @$pb.TagNumber(21)
  $core.bool get isBlocked => $_getBF(20);
  @$pb.TagNumber(21)
  set isBlocked($core.bool v) { $_setBool(20, v); }
  @$pb.TagNumber(21)
  $core.bool hasIsBlocked() => $_has(20);
  @$pb.TagNumber(21)
  void clearIsBlocked() => clearField(21);

  @$pb.TagNumber(22)
  $core.int get slowmodeSeconds => $_getIZ(21);
  @$pb.TagNumber(22)
  set slowmodeSeconds($core.int v) { $_setSignedInt32(21, v); }
  @$pb.TagNumber(22)
  $core.bool hasSlowmodeSeconds() => $_has(21);
  @$pb.TagNumber(22)
  void clearSlowmodeSeconds() => clearField(22);

  @$pb.TagNumber(23)
  $fixnum.Int64 get slowmodeNextSendDate => $_getI64(22);
  @$pb.TagNumber(23)
  set slowmodeNextSendDate($fixnum.Int64 v) { $_setInt64(22, v); }
  @$pb.TagNumber(23)
  $core.bool hasSlowmodeNextSendDate() => $_has(22);
  @$pb.TagNumber(23)
  void clearSlowmodeNextSendDate() => clearField(23);

  @$pb.TagNumber(24)
  $core.int get starsToSend => $_getIZ(23);
  @$pb.TagNumber(24)
  set starsToSend($core.int v) { $_setSignedInt32(23, v); }
  @$pb.TagNumber(24)
  $core.bool hasStarsToSend() => $_has(23);
  @$pb.TagNumber(24)
  void clearStarsToSend() => clearField(24);

  @$pb.TagNumber(25)
  $core.int get ttlPeriod => $_getIZ(24);
  @$pb.TagNumber(25)
  set ttlPeriod($core.int v) { $_setSignedInt32(24, v); }
  @$pb.TagNumber(25)
  $core.bool hasTtlPeriod() => $_has(24);
  @$pb.TagNumber(25)
  void clearTtlPeriod() => clearField(25);

  @$pb.TagNumber(26)
  $core.String get emojiStatusId => $_getSZ(25);
  @$pb.TagNumber(26)
  set emojiStatusId($core.String v) { $_setString(25, v); }
  @$pb.TagNumber(26)
  $core.bool hasEmojiStatusId() => $_has(25);
  @$pb.TagNumber(26)
  void clearEmojiStatusId() => clearField(26);

  @$pb.TagNumber(27)
  $core.bool get isForum => $_getBF(26);
  @$pb.TagNumber(27)
  set isForum($core.bool v) { $_setBool(26, v); }
  @$pb.TagNumber(27)
  $core.bool hasIsForum() => $_has(26);
  @$pb.TagNumber(27)
  void clearIsForum() => clearField(27);
}

class EngineGetChatListRequest extends $pb.GeneratedMessage {
  factory EngineGetChatListRequest({
    $core.String? accountId,
    $core.bool? archived,
    $core.int? limit,
    $core.int? offset,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (archived != null) {
      $result.archived = archived;
    }
    if (limit != null) {
      $result.limit = limit;
    }
    if (offset != null) {
      $result.offset = offset;
    }
    return $result;
  }
  EngineGetChatListRequest._() : super();
  factory EngineGetChatListRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetChatListRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetChatListRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOB(2, _omitFieldNames ? '' : 'archived')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'offset', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetChatListRequest clone() => EngineGetChatListRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetChatListRequest copyWith(void Function(EngineGetChatListRequest) updates) => super.copyWith((message) => updates(message as EngineGetChatListRequest)) as EngineGetChatListRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetChatListRequest create() => EngineGetChatListRequest._();
  EngineGetChatListRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetChatListRequest> createRepeated() => $pb.PbList<EngineGetChatListRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetChatListRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetChatListRequest>(create);
  static EngineGetChatListRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get archived => $_getBF(1);
  @$pb.TagNumber(2)
  set archived($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasArchived() => $_has(1);
  @$pb.TagNumber(2)
  void clearArchived() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get limit => $_getIZ(2);
  @$pb.TagNumber(3)
  set limit($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLimit() => $_has(2);
  @$pb.TagNumber(3)
  void clearLimit() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get offset => $_getIZ(3);
  @$pb.TagNumber(4)
  set offset($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOffset() => $_has(3);
  @$pb.TagNumber(4)
  void clearOffset() => clearField(4);
}

class EngineGetChatListResponse extends $pb.GeneratedMessage {
  factory EngineGetChatListResponse({
    $core.Iterable<EngineChatInfo>? chats,
  }) {
    final $result = create();
    if (chats != null) {
      $result.chats.addAll(chats);
    }
    return $result;
  }
  EngineGetChatListResponse._() : super();
  factory EngineGetChatListResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetChatListResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetChatListResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineChatInfo>(1, _omitFieldNames ? '' : 'chats', $pb.PbFieldType.PM, subBuilder: EngineChatInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetChatListResponse clone() => EngineGetChatListResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetChatListResponse copyWith(void Function(EngineGetChatListResponse) updates) => super.copyWith((message) => updates(message as EngineGetChatListResponse)) as EngineGetChatListResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetChatListResponse create() => EngineGetChatListResponse._();
  EngineGetChatListResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetChatListResponse> createRepeated() => $pb.PbList<EngineGetChatListResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetChatListResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetChatListResponse>(create);
  static EngineGetChatListResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineChatInfo> get chats => $_getList(0);
}

class EngineSaveDraftRequest extends $pb.GeneratedMessage {
  factory EngineSaveDraftRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? text,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (text != null) {
      $result.text = text;
    }
    return $result;
  }
  EngineSaveDraftRequest._() : super();
  factory EngineSaveDraftRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSaveDraftRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSaveDraftRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'text')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSaveDraftRequest clone() => EngineSaveDraftRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSaveDraftRequest copyWith(void Function(EngineSaveDraftRequest) updates) => super.copyWith((message) => updates(message as EngineSaveDraftRequest)) as EngineSaveDraftRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSaveDraftRequest create() => EngineSaveDraftRequest._();
  EngineSaveDraftRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSaveDraftRequest> createRepeated() => $pb.PbList<EngineSaveDraftRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSaveDraftRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSaveDraftRequest>(create);
  static EngineSaveDraftRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get text => $_getSZ(2);
  @$pb.TagNumber(3)
  set text($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasText() => $_has(2);
  @$pb.TagNumber(3)
  void clearText() => clearField(3);
}

class EngineMuteChatRequest extends $pb.GeneratedMessage {
  factory EngineMuteChatRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.bool? muted,
    $core.int? durationSeconds,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (muted != null) {
      $result.muted = muted;
    }
    if (durationSeconds != null) {
      $result.durationSeconds = durationSeconds;
    }
    return $result;
  }
  EngineMuteChatRequest._() : super();
  factory EngineMuteChatRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineMuteChatRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineMuteChatRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOB(3, _omitFieldNames ? '' : 'muted')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'durationSeconds', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineMuteChatRequest clone() => EngineMuteChatRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineMuteChatRequest copyWith(void Function(EngineMuteChatRequest) updates) => super.copyWith((message) => updates(message as EngineMuteChatRequest)) as EngineMuteChatRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineMuteChatRequest create() => EngineMuteChatRequest._();
  EngineMuteChatRequest createEmptyInstance() => create();
  static $pb.PbList<EngineMuteChatRequest> createRepeated() => $pb.PbList<EngineMuteChatRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineMuteChatRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineMuteChatRequest>(create);
  static EngineMuteChatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get muted => $_getBF(2);
  @$pb.TagNumber(3)
  set muted($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMuted() => $_has(2);
  @$pb.TagNumber(3)
  void clearMuted() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get durationSeconds => $_getIZ(3);
  @$pb.TagNumber(4)
  set durationSeconds($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDurationSeconds() => $_has(3);
  @$pb.TagNumber(4)
  void clearDurationSeconds() => clearField(4);
}

class EnginePinChatRequest extends $pb.GeneratedMessage {
  factory EnginePinChatRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.bool? pinned,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (pinned != null) {
      $result.pinned = pinned;
    }
    return $result;
  }
  EnginePinChatRequest._() : super();
  factory EnginePinChatRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EnginePinChatRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EnginePinChatRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOB(3, _omitFieldNames ? '' : 'pinned')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EnginePinChatRequest clone() => EnginePinChatRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EnginePinChatRequest copyWith(void Function(EnginePinChatRequest) updates) => super.copyWith((message) => updates(message as EnginePinChatRequest)) as EnginePinChatRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EnginePinChatRequest create() => EnginePinChatRequest._();
  EnginePinChatRequest createEmptyInstance() => create();
  static $pb.PbList<EnginePinChatRequest> createRepeated() => $pb.PbList<EnginePinChatRequest>();
  @$core.pragma('dart2js:noInline')
  static EnginePinChatRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EnginePinChatRequest>(create);
  static EnginePinChatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get pinned => $_getBF(2);
  @$pb.TagNumber(3)
  set pinned($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPinned() => $_has(2);
  @$pb.TagNumber(3)
  void clearPinned() => clearField(3);
}

class EngineArchiveChatRequest extends $pb.GeneratedMessage {
  factory EngineArchiveChatRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.bool? archived,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (archived != null) {
      $result.archived = archived;
    }
    return $result;
  }
  EngineArchiveChatRequest._() : super();
  factory EngineArchiveChatRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineArchiveChatRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineArchiveChatRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOB(3, _omitFieldNames ? '' : 'archived')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineArchiveChatRequest clone() => EngineArchiveChatRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineArchiveChatRequest copyWith(void Function(EngineArchiveChatRequest) updates) => super.copyWith((message) => updates(message as EngineArchiveChatRequest)) as EngineArchiveChatRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineArchiveChatRequest create() => EngineArchiveChatRequest._();
  EngineArchiveChatRequest createEmptyInstance() => create();
  static $pb.PbList<EngineArchiveChatRequest> createRepeated() => $pb.PbList<EngineArchiveChatRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineArchiveChatRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineArchiveChatRequest>(create);
  static EngineArchiveChatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.bool get archived => $_getBF(2);
  @$pb.TagNumber(3)
  set archived($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasArchived() => $_has(2);
  @$pb.TagNumber(3)
  void clearArchived() => clearField(3);
}

class EngineSetHistoryTTLRequest extends $pb.GeneratedMessage {
  factory EngineSetHistoryTTLRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.int? period,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (period != null) {
      $result.period = period;
    }
    return $result;
  }
  EngineSetHistoryTTLRequest._() : super();
  factory EngineSetHistoryTTLRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSetHistoryTTLRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSetHistoryTTLRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'period', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  EngineSetHistoryTTLRequest clone() => EngineSetHistoryTTLRequest()..mergeFromMessage(this);

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSetHistoryTTLRequest create() => EngineSetHistoryTTLRequest._();
  EngineSetHistoryTTLRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSetHistoryTTLRequest> createRepeated() => $pb.PbList<EngineSetHistoryTTLRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSetHistoryTTLRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSetHistoryTTLRequest>(create);
  static EngineSetHistoryTTLRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get period => $_getIZ(2);
  @$pb.TagNumber(3)
  set period($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPeriod() => $_has(2);
  @$pb.TagNumber(3)
  void clearPeriod() => clearField(3);
}

class EngineMarkChatReadRequest extends $pb.GeneratedMessage {
  factory EngineMarkChatReadRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? upToMsgId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (upToMsgId != null) {
      $result.upToMsgId = upToMsgId;
    }
    return $result;
  }
  EngineMarkChatReadRequest._() : super();
  factory EngineMarkChatReadRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineMarkChatReadRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineMarkChatReadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'upToMsgId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineMarkChatReadRequest clone() => EngineMarkChatReadRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineMarkChatReadRequest copyWith(void Function(EngineMarkChatReadRequest) updates) => super.copyWith((message) => updates(message as EngineMarkChatReadRequest)) as EngineMarkChatReadRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineMarkChatReadRequest create() => EngineMarkChatReadRequest._();
  EngineMarkChatReadRequest createEmptyInstance() => create();
  static $pb.PbList<EngineMarkChatReadRequest> createRepeated() => $pb.PbList<EngineMarkChatReadRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineMarkChatReadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineMarkChatReadRequest>(create);
  static EngineMarkChatReadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get upToMsgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set upToMsgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUpToMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearUpToMsgId() => clearField(3);
}

class EngineBlockUserRequest extends $pb.GeneratedMessage {
  factory EngineBlockUserRequest({
    $core.String? accountId,
    $core.String? userId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    return $result;
  }
  EngineBlockUserRequest._() : super();
  factory EngineBlockUserRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineBlockUserRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineBlockUserRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineBlockUserRequest clone() => EngineBlockUserRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineBlockUserRequest copyWith(void Function(EngineBlockUserRequest) updates) => super.copyWith((message) => updates(message as EngineBlockUserRequest)) as EngineBlockUserRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineBlockUserRequest create() => EngineBlockUserRequest._();
  EngineBlockUserRequest createEmptyInstance() => create();
  static $pb.PbList<EngineBlockUserRequest> createRepeated() => $pb.PbList<EngineBlockUserRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineBlockUserRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineBlockUserRequest>(create);
  static EngineBlockUserRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(2)
  set userId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => clearField(2);
}

class EngineUnblockUserRequest extends $pb.GeneratedMessage {
  factory EngineUnblockUserRequest({
    $core.String? accountId,
    $core.String? userId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (userId != null) {
      $result.userId = userId;
    }
    return $result;
  }
  EngineUnblockUserRequest._() : super();
  factory EngineUnblockUserRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineUnblockUserRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineUnblockUserRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineUnblockUserRequest clone() => EngineUnblockUserRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineUnblockUserRequest copyWith(void Function(EngineUnblockUserRequest) updates) => super.copyWith((message) => updates(message as EngineUnblockUserRequest)) as EngineUnblockUserRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineUnblockUserRequest create() => EngineUnblockUserRequest._();
  EngineUnblockUserRequest createEmptyInstance() => create();
  static $pb.PbList<EngineUnblockUserRequest> createRepeated() => $pb.PbList<EngineUnblockUserRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineUnblockUserRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineUnblockUserRequest>(create);
  static EngineUnblockUserRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get userId => $_getSZ(1);
  @$pb.TagNumber(2)
  set userId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUserId() => $_has(1);
  @$pb.TagNumber(2)
  void clearUserId() => clearField(2);
}

class EngineAddContactRequest extends $pb.GeneratedMessage {
  factory EngineAddContactRequest({
    $core.String? accountId,
    $core.String? phone,
    $core.String? firstName,
    $core.String? lastName,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (phone != null) {
      $result.phone = phone;
    }
    if (firstName != null) {
      $result.firstName = firstName;
    }
    if (lastName != null) {
      $result.lastName = lastName;
    }
    return $result;
  }
  EngineAddContactRequest._() : super();
  factory EngineAddContactRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineAddContactRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineAddContactRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'phone')
    ..aOS(3, _omitFieldNames ? '' : 'firstName')
    ..aOS(4, _omitFieldNames ? '' : 'lastName')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineAddContactRequest clone() => EngineAddContactRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineAddContactRequest copyWith(void Function(EngineAddContactRequest) updates) => super.copyWith((message) => updates(message as EngineAddContactRequest)) as EngineAddContactRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineAddContactRequest create() => EngineAddContactRequest._();
  EngineAddContactRequest createEmptyInstance() => create();
  static $pb.PbList<EngineAddContactRequest> createRepeated() => $pb.PbList<EngineAddContactRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineAddContactRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineAddContactRequest>(create);
  static EngineAddContactRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get phone => $_getSZ(1);
  @$pb.TagNumber(2)
  set phone($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasPhone() => $_has(1);
  @$pb.TagNumber(2)
  void clearPhone() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get firstName => $_getSZ(2);
  @$pb.TagNumber(3)
  set firstName($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFirstName() => $_has(2);
  @$pb.TagNumber(3)
  void clearFirstName() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get lastName => $_getSZ(3);
  @$pb.TagNumber(4)
  set lastName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLastName() => $_has(3);
  @$pb.TagNumber(4)
  void clearLastName() => clearField(4);
}

class EngineGetForumTopicsRequest extends $pb.GeneratedMessage {
  factory EngineGetForumTopicsRequest({
    $core.String? accountId,
    $core.String? chatId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  EngineGetForumTopicsRequest._() : super();
  factory EngineGetForumTopicsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetForumTopicsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetForumTopicsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetForumTopicsRequest clone() => EngineGetForumTopicsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetForumTopicsRequest copyWith(void Function(EngineGetForumTopicsRequest) updates) => super.copyWith((message) => updates(message as EngineGetForumTopicsRequest)) as EngineGetForumTopicsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetForumTopicsRequest create() => EngineGetForumTopicsRequest._();
  EngineGetForumTopicsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetForumTopicsRequest> createRepeated() => $pb.PbList<EngineGetForumTopicsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetForumTopicsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetForumTopicsRequest>(create);
  static EngineGetForumTopicsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class EngineForumTopic extends $pb.GeneratedMessage {
  factory EngineForumTopic({
    $core.String? id,
    $core.String? title,
    $core.int? colorId,
    $fixnum.Int64? iconEmojiId,
    $core.String? creatorId,
    $fixnum.Int64? creationDate,
    $core.bool? isClosed,
    $core.bool? isHidden,
    $core.bool? isMy,
    $core.bool? isPinned,
    $core.int? unreadCount,
    $core.int? unreadMentions,
    $core.int? unreadReactions,
    $core.String? topMessageId,
    $core.int? readInboxMaxId,
    $core.int? readOutboxMaxId,
    $core.String? parentId,
    $core.bool? canEdit,
    $core.bool? canDelete,
    $core.bool? canToggleClosed,
    $core.bool? canTogglePinned,
  }) {
    final $result = create();
    if (id != null) $result.id = id;
    if (title != null) $result.title = title;
    if (colorId != null) $result.colorId = colorId;
    if (iconEmojiId != null) $result.iconEmojiId = iconEmojiId;
    if (creatorId != null) $result.creatorId = creatorId;
    if (creationDate != null) $result.creationDate = creationDate;
    if (isClosed != null) $result.isClosed = isClosed;
    if (isHidden != null) $result.isHidden = isHidden;
    if (isMy != null) $result.isMy = isMy;
    if (isPinned != null) $result.isPinned = isPinned;
    if (unreadCount != null) $result.unreadCount = unreadCount;
    if (unreadMentions != null) $result.unreadMentions = unreadMentions;
    if (unreadReactions != null) $result.unreadReactions = unreadReactions;
    if (topMessageId != null) $result.topMessageId = topMessageId;
    if (readInboxMaxId != null) $result.readInboxMaxId = readInboxMaxId;
    if (readOutboxMaxId != null) $result.readOutboxMaxId = readOutboxMaxId;
    if (parentId != null) $result.parentId = parentId;
    if (canEdit != null) $result.canEdit = canEdit;
    if (canDelete != null) $result.canDelete = canDelete;
    if (canToggleClosed != null) $result.canToggleClosed = canToggleClosed;
    if (canTogglePinned != null) $result.canTogglePinned = canTogglePinned;
    return $result;
  }
  EngineForumTopic._() : super();
  factory EngineForumTopic.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineForumTopic.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineForumTopic', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'colorId', $pb.PbFieldType.O3)
    ..aInt64(4, _omitFieldNames ? '' : 'iconEmojiId')
    ..aOS(5, _omitFieldNames ? '' : 'creatorId')
    ..aInt64(6, _omitFieldNames ? '' : 'creationDate')
    ..aOB(7, _omitFieldNames ? '' : 'isClosed')
    ..aOB(8, _omitFieldNames ? '' : 'isHidden')
    ..aOB(9, _omitFieldNames ? '' : 'isMy')
    ..aOB(10, _omitFieldNames ? '' : 'isPinned')
    ..a<$core.int>(11, _omitFieldNames ? '' : 'unreadCount', $pb.PbFieldType.O3)
    ..a<$core.int>(12, _omitFieldNames ? '' : 'unreadMentions', $pb.PbFieldType.O3)
    ..a<$core.int>(13, _omitFieldNames ? '' : 'unreadReactions', $pb.PbFieldType.O3)
    ..aOS(14, _omitFieldNames ? '' : 'topMessageId')
    ..a<$core.int>(15, _omitFieldNames ? '' : 'readInboxMaxId', $pb.PbFieldType.O3)
    ..a<$core.int>(16, _omitFieldNames ? '' : 'readOutboxMaxId', $pb.PbFieldType.O3)
    ..aOS(17, _omitFieldNames ? '' : 'parentId')
    ..aOB(18, _omitFieldNames ? '' : 'canEdit')
    ..aOB(19, _omitFieldNames ? '' : 'canDelete')
    ..aOB(20, _omitFieldNames ? '' : 'canToggleClosed')
    ..aOB(21, _omitFieldNames ? '' : 'canTogglePinned')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineForumTopic clone() => EngineForumTopic()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineForumTopic copyWith(void Function(EngineForumTopic) updates) => super.copyWith((message) => updates(message as EngineForumTopic)) as EngineForumTopic;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineForumTopic create() => EngineForumTopic._();
  EngineForumTopic createEmptyInstance() => create();
  static $pb.PbList<EngineForumTopic> createRepeated() => $pb.PbList<EngineForumTopic>();
  @$core.pragma('dart2js:noInline')
  static EngineForumTopic getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineForumTopic>(create);
  static EngineForumTopic? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.int get colorId => $_getIZ(2);
  @$pb.TagNumber(3)
  set colorId($core.int v) { $_setSignedInt32(2, v); }

  @$pb.TagNumber(4)
  $fixnum.Int64 get iconEmojiId => $_getI64(3);
  @$pb.TagNumber(4)
  set iconEmojiId($fixnum.Int64 v) { $_setInt64(3, v); }

  @$pb.TagNumber(5)
  $core.String get creatorId => $_getSZ(4);
  @$pb.TagNumber(5)
  set creatorId($core.String v) { $_setString(4, v); }

  @$pb.TagNumber(6)
  $fixnum.Int64 get creationDate => $_getI64(5);
  @$pb.TagNumber(6)
  set creationDate($fixnum.Int64 v) { $_setInt64(5, v); }

  @$pb.TagNumber(7)
  $core.bool get isClosed => $_getBF(6);
  @$pb.TagNumber(7)
  set isClosed($core.bool v) { $_setBool(6, v); }

  @$pb.TagNumber(8)
  $core.bool get isHidden => $_getBF(7);
  @$pb.TagNumber(8)
  set isHidden($core.bool v) { $_setBool(7, v); }

  @$pb.TagNumber(9)
  $core.bool get isMy => $_getBF(8);
  @$pb.TagNumber(9)
  set isMy($core.bool v) { $_setBool(8, v); }

  @$pb.TagNumber(10)
  $core.bool get isPinned => $_getBF(9);
  @$pb.TagNumber(10)
  set isPinned($core.bool v) { $_setBool(9, v); }

  @$pb.TagNumber(11)
  $core.int get unreadCount => $_getIZ(10);
  @$pb.TagNumber(11)
  set unreadCount($core.int v) { $_setSignedInt32(10, v); }

  @$pb.TagNumber(12)
  $core.int get unreadMentions => $_getIZ(11);
  @$pb.TagNumber(12)
  set unreadMentions($core.int v) { $_setSignedInt32(11, v); }

  @$pb.TagNumber(13)
  $core.int get unreadReactions => $_getIZ(12);
  @$pb.TagNumber(13)
  set unreadReactions($core.int v) { $_setSignedInt32(12, v); }

  @$pb.TagNumber(14)
  $core.String get topMessageId => $_getSZ(13);
  @$pb.TagNumber(14)
  set topMessageId($core.String v) { $_setString(13, v); }

  @$pb.TagNumber(15)
  $core.int get readInboxMaxId => $_getIZ(14);
  @$pb.TagNumber(15)
  set readInboxMaxId($core.int v) { $_setSignedInt32(14, v); }

  @$pb.TagNumber(16)
  $core.int get readOutboxMaxId => $_getIZ(15);
  @$pb.TagNumber(16)
  set readOutboxMaxId($core.int v) { $_setSignedInt32(15, v); }

  @$pb.TagNumber(17)
  $core.String get parentId => $_getSZ(16);
  @$pb.TagNumber(17)
  set parentId($core.String v) { $_setString(16, v); }

  @$pb.TagNumber(18)
  $core.bool get canEdit => $_getBF(17);
  @$pb.TagNumber(18)
  set canEdit($core.bool v) { $_setBool(17, v); }

  @$pb.TagNumber(19)
  $core.bool get canDelete => $_getBF(18);
  @$pb.TagNumber(19)
  set canDelete($core.bool v) { $_setBool(18, v); }

  @$pb.TagNumber(20)
  $core.bool get canToggleClosed => $_getBF(19);
  @$pb.TagNumber(20)
  set canToggleClosed($core.bool v) { $_setBool(19, v); }

  @$pb.TagNumber(21)
  $core.bool get canTogglePinned => $_getBF(20);
  @$pb.TagNumber(21)
  set canTogglePinned($core.bool v) { $_setBool(20, v); }
}

class EngineGetForumTopicsResponse extends $pb.GeneratedMessage {
  factory EngineGetForumTopicsResponse({
    $core.Iterable<EngineForumTopic>? topics,
  }) {
    final $result = create();
    if (topics != null) {
      $result.topics.addAll(topics);
    }
    return $result;
  }
  EngineGetForumTopicsResponse._() : super();
  factory EngineGetForumTopicsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetForumTopicsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetForumTopicsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineForumTopic>(1, _omitFieldNames ? '' : 'topics', $pb.PbFieldType.PM, subBuilder: EngineForumTopic.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetForumTopicsResponse clone() => EngineGetForumTopicsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetForumTopicsResponse copyWith(void Function(EngineGetForumTopicsResponse) updates) => super.copyWith((message) => updates(message as EngineGetForumTopicsResponse)) as EngineGetForumTopicsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetForumTopicsResponse create() => EngineGetForumTopicsResponse._();
  EngineGetForumTopicsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetForumTopicsResponse> createRepeated() => $pb.PbList<EngineGetForumTopicsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetForumTopicsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetForumTopicsResponse>(create);
  static EngineGetForumTopicsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineForumTopic> get topics => $_getList(0);
}

class EngineCreateForumTopicRequest extends $pb.GeneratedMessage {
  factory EngineCreateForumTopicRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? title,
    $core.int? colorId,
    $fixnum.Int64? iconEmojiId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (title != null) $result.title = title;
    if (colorId != null) $result.colorId = colorId;
    if (iconEmojiId != null) $result.iconEmojiId = iconEmojiId;
    return $result;
  }
  EngineCreateForumTopicRequest._() : super();
  factory EngineCreateForumTopicRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCreateForumTopicRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'colorId', $pb.PbFieldType.O3)
    ..aInt64(5, _omitFieldNames ? '' : 'iconEmojiId')
    ..hasRequiredFields = false
  ;

  EngineCreateForumTopicRequest clone() => EngineCreateForumTopicRequest()..mergeFromMessage(this);
  EngineCreateForumTopicRequest copyWith(void Function(EngineCreateForumTopicRequest) updates) => super.copyWith((message) => updates(message as EngineCreateForumTopicRequest)) as EngineCreateForumTopicRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineCreateForumTopicRequest create() => EngineCreateForumTopicRequest._();
  EngineCreateForumTopicRequest createEmptyInstance() => create();
  static $pb.PbList<EngineCreateForumTopicRequest> createRepeated() => $pb.PbList<EngineCreateForumTopicRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineCreateForumTopicRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCreateForumTopicRequest>(create);
  static EngineCreateForumTopicRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String v) { $_setString(2, v); }

  @$pb.TagNumber(4)
  $core.int get colorId => $_getIZ(3);
  @$pb.TagNumber(4)
  set colorId($core.int v) { $_setSignedInt32(3, v); }

  @$pb.TagNumber(5)
  $fixnum.Int64 get iconEmojiId => $_getI64(4);
  @$pb.TagNumber(5)
  set iconEmojiId($fixnum.Int64 v) { $_setInt64(4, v); }
}

class EngineCreateForumTopicResponse extends $pb.GeneratedMessage {
  factory EngineCreateForumTopicResponse({
    $fixnum.Int64? topicId,
  }) {
    final $result = create();
    if (topicId != null) $result.topicId = topicId;
    return $result;
  }
  EngineCreateForumTopicResponse._() : super();
  factory EngineCreateForumTopicResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCreateForumTopicResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'topicId')
    ..hasRequiredFields = false
  ;

  EngineCreateForumTopicResponse clone() => EngineCreateForumTopicResponse()..mergeFromMessage(this);
  EngineCreateForumTopicResponse copyWith(void Function(EngineCreateForumTopicResponse) updates) => super.copyWith((message) => updates(message as EngineCreateForumTopicResponse)) as EngineCreateForumTopicResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineCreateForumTopicResponse create() => EngineCreateForumTopicResponse._();
  EngineCreateForumTopicResponse createEmptyInstance() => create();
  static $pb.PbList<EngineCreateForumTopicResponse> createRepeated() => $pb.PbList<EngineCreateForumTopicResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineCreateForumTopicResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCreateForumTopicResponse>(create);
  static EngineCreateForumTopicResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get topicId => $_getI64(0);
  @$pb.TagNumber(1)
  set topicId($fixnum.Int64 v) { $_setInt64(0, v); }
}

class EngineEditForumTopicRequest extends $pb.GeneratedMessage {
  factory EngineEditForumTopicRequest({
    $core.String? accountId,
    $core.String? chatId,
    $fixnum.Int64? topicId,
    $core.String? title,
    $core.int? colorId,
    $fixnum.Int64? iconEmojiId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (topicId != null) $result.topicId = topicId;
    if (title != null) $result.title = title;
    if (colorId != null) $result.colorId = colorId;
    if (iconEmojiId != null) $result.iconEmojiId = iconEmojiId;
    return $result;
  }
  EngineEditForumTopicRequest._() : super();
  factory EngineEditForumTopicRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineEditForumTopicRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aInt64(3, _omitFieldNames ? '' : 'topicId')
    ..aOS(4, _omitFieldNames ? '' : 'title')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'colorId', $pb.PbFieldType.O3)
    ..aInt64(6, _omitFieldNames ? '' : 'iconEmojiId')
    ..hasRequiredFields = false
  ;

  EngineEditForumTopicRequest clone() => EngineEditForumTopicRequest()..mergeFromMessage(this);
  EngineEditForumTopicRequest copyWith(void Function(EngineEditForumTopicRequest) updates) => super.copyWith((message) => updates(message as EngineEditForumTopicRequest)) as EngineEditForumTopicRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineEditForumTopicRequest create() => EngineEditForumTopicRequest._();
  EngineEditForumTopicRequest createEmptyInstance() => create();
  static $pb.PbList<EngineEditForumTopicRequest> createRepeated() => $pb.PbList<EngineEditForumTopicRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineEditForumTopicRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineEditForumTopicRequest>(create);
  static EngineEditForumTopicRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $fixnum.Int64 get topicId => $_getI64(2);
  @$pb.TagNumber(3)
  set topicId($fixnum.Int64 v) { $_setInt64(2, v); }

  @$pb.TagNumber(4)
  $core.String get title => $_getSZ(3);
  @$pb.TagNumber(4)
  set title($core.String v) { $_setString(3, v); }

  @$pb.TagNumber(5)
  $core.int get colorId => $_getIZ(4);
  @$pb.TagNumber(5)
  set colorId($core.int v) { $_setSignedInt32(4, v); }

  @$pb.TagNumber(6)
  $fixnum.Int64 get iconEmojiId => $_getI64(5);
  @$pb.TagNumber(6)
  set iconEmojiId($fixnum.Int64 v) { $_setInt64(5, v); }
}

class EngineCachedMessage extends $pb.GeneratedMessage {
  factory EngineCachedMessage({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.String? localId,
    $core.String? senderId,
    $core.String? senderName,
    $core.String? contentText,
    $core.List<$core.int>? contentRaw,
    $core.List<$core.int>? contentRich,
    $fixnum.Int64? timestamp,
    $fixnum.Int64? editedAt,
    $core.int? status,
    $core.String? replyToId,
    $core.String? replyPreview,
    $core.String? forwardFrom,
    $core.bool? isPinned,
    $core.bool? hasMedia,
    $core.int? mediaType,
    $core.String? mediaFileName,
    $core.String? mediaMimeType,
    $fixnum.Int64? mediaFileSize,
    $core.String? mediaThumbB64,
    $core.String? mediaLocalPath,
    $core.int? mediaWidth,
    $core.int? mediaHeight,
    $core.int? mediaDuration,
    $core.int? mediaDownloadState,
    $core.bool? isOutgoing,
    $core.String? senderRank,
    $core.int? senderColorId,
    $core.bool? isService,
    $core.String? groupedId,
    $core.String? mediaRemoteRef,
    $core.String? mediaExtra,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (localId != null) {
      $result.localId = localId;
    }
    if (senderId != null) {
      $result.senderId = senderId;
    }
    if (senderName != null) {
      $result.senderName = senderName;
    }
    if (contentText != null) {
      $result.contentText = contentText;
    }
    if (contentRaw != null) {
      $result.contentRaw = contentRaw;
    }
    if (contentRich != null) {
      $result.contentRich = contentRich;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (editedAt != null) {
      $result.editedAt = editedAt;
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
    if (isPinned != null) {
      $result.isPinned = isPinned;
    }
    if (hasMedia != null) {
      $result.hasMedia = hasMedia;
    }
    if (mediaType != null) {
      $result.mediaType = mediaType;
    }
    if (mediaFileName != null) {
      $result.mediaFileName = mediaFileName;
    }
    if (mediaMimeType != null) {
      $result.mediaMimeType = mediaMimeType;
    }
    if (mediaFileSize != null) {
      $result.mediaFileSize = mediaFileSize;
    }
    if (mediaThumbB64 != null) {
      $result.mediaThumbB64 = mediaThumbB64;
    }
    if (mediaLocalPath != null) {
      $result.mediaLocalPath = mediaLocalPath;
    }
    if (mediaWidth != null) {
      $result.mediaWidth = mediaWidth;
    }
    if (mediaHeight != null) {
      $result.mediaHeight = mediaHeight;
    }
    if (mediaDuration != null) {
      $result.mediaDuration = mediaDuration;
    }
    if (mediaDownloadState != null) {
      $result.mediaDownloadState = mediaDownloadState;
    }
    if (isOutgoing != null) {
      $result.isOutgoing = isOutgoing;
    }
    if (senderRank != null) {
      $result.senderRank = senderRank;
    }
    if (senderColorId != null) {
      $result.senderColorId = senderColorId;
    }
    if (isService != null) {
      $result.isService = isService;
    }
    if (groupedId != null) {
      $result.groupedId = groupedId;
    }
    if (mediaRemoteRef != null) {
      $result.mediaRemoteRef = mediaRemoteRef;
    }
    if (mediaExtra != null) {
      $result.mediaExtra = mediaExtra;
    }
    return $result;
  }
  EngineCachedMessage._() : super();
  factory EngineCachedMessage.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineCachedMessage.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCachedMessage', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..aOS(4, _omitFieldNames ? '' : 'localId')
    ..aOS(5, _omitFieldNames ? '' : 'senderId')
    ..aOS(6, _omitFieldNames ? '' : 'senderName')
    ..aOS(7, _omitFieldNames ? '' : 'contentText')
    ..a<$core.List<$core.int>>(8, _omitFieldNames ? '' : 'contentRaw', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(9, _omitFieldNames ? '' : 'contentRich', $pb.PbFieldType.OY)
    ..aInt64(10, _omitFieldNames ? '' : 'timestamp')
    ..aInt64(11, _omitFieldNames ? '' : 'editedAt')
    ..a<$core.int>(12, _omitFieldNames ? '' : 'status', $pb.PbFieldType.O3)
    ..aOS(13, _omitFieldNames ? '' : 'replyToId')
    ..aOS(14, _omitFieldNames ? '' : 'replyPreview')
    ..aOS(15, _omitFieldNames ? '' : 'forwardFrom')
    ..aOB(16, _omitFieldNames ? '' : 'isPinned')
    ..aOB(17, _omitFieldNames ? '' : 'hasMedia')
    ..a<$core.int>(18, _omitFieldNames ? '' : 'mediaType', $pb.PbFieldType.O3)
    ..aOS(19, _omitFieldNames ? '' : 'mediaFileName')
    ..aOS(20, _omitFieldNames ? '' : 'mediaMimeType')
    ..aInt64(21, _omitFieldNames ? '' : 'mediaFileSize')
    ..aOS(22, _omitFieldNames ? '' : 'mediaThumbB64')
    ..aOS(23, _omitFieldNames ? '' : 'mediaLocalPath')
    ..a<$core.int>(24, _omitFieldNames ? '' : 'mediaWidth', $pb.PbFieldType.O3)
    ..a<$core.int>(25, _omitFieldNames ? '' : 'mediaHeight', $pb.PbFieldType.O3)
    ..a<$core.int>(26, _omitFieldNames ? '' : 'mediaDuration', $pb.PbFieldType.O3)
    ..a<$core.int>(27, _omitFieldNames ? '' : 'mediaDownloadState', $pb.PbFieldType.O3)
    ..aOB(28, _omitFieldNames ? '' : 'isOutgoing')
    ..aOS(29, _omitFieldNames ? '' : 'senderRank')
    ..a<$core.int>(30, _omitFieldNames ? '' : 'senderColorId', $pb.PbFieldType.O3)
    ..aOB(31, _omitFieldNames ? '' : 'isService')
    ..aOS(32, _omitFieldNames ? '' : 'groupedId')
    ..aOS(33, _omitFieldNames ? '' : 'mediaRemoteRef')
    ..aOS(34, _omitFieldNames ? '' : 'mediaExtra')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineCachedMessage clone() => EngineCachedMessage()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineCachedMessage copyWith(void Function(EngineCachedMessage) updates) => super.copyWith((message) => updates(message as EngineCachedMessage)) as EngineCachedMessage;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineCachedMessage create() => EngineCachedMessage._();
  EngineCachedMessage createEmptyInstance() => create();
  static $pb.PbList<EngineCachedMessage> createRepeated() => $pb.PbList<EngineCachedMessage>();
  @$core.pragma('dart2js:noInline')
  static EngineCachedMessage getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCachedMessage>(create);
  static EngineCachedMessage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get localId => $_getSZ(3);
  @$pb.TagNumber(4)
  set localId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLocalId() => $_has(3);
  @$pb.TagNumber(4)
  void clearLocalId() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get senderId => $_getSZ(4);
  @$pb.TagNumber(5)
  set senderId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSenderId() => $_has(4);
  @$pb.TagNumber(5)
  void clearSenderId() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get senderName => $_getSZ(5);
  @$pb.TagNumber(6)
  set senderName($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSenderName() => $_has(5);
  @$pb.TagNumber(6)
  void clearSenderName() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get contentText => $_getSZ(6);
  @$pb.TagNumber(7)
  set contentText($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasContentText() => $_has(6);
  @$pb.TagNumber(7)
  void clearContentText() => clearField(7);

  @$pb.TagNumber(8)
  $core.List<$core.int> get contentRaw => $_getN(7);
  @$pb.TagNumber(8)
  set contentRaw($core.List<$core.int> v) { $_setBytes(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasContentRaw() => $_has(7);
  @$pb.TagNumber(8)
  void clearContentRaw() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.int> get contentRich => $_getN(8);
  @$pb.TagNumber(9)
  set contentRich($core.List<$core.int> v) { $_setBytes(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasContentRich() => $_has(8);
  @$pb.TagNumber(9)
  void clearContentRich() => clearField(9);

  @$pb.TagNumber(10)
  $fixnum.Int64 get timestamp => $_getI64(9);
  @$pb.TagNumber(10)
  set timestamp($fixnum.Int64 v) { $_setInt64(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasTimestamp() => $_has(9);
  @$pb.TagNumber(10)
  void clearTimestamp() => clearField(10);

  @$pb.TagNumber(11)
  $fixnum.Int64 get editedAt => $_getI64(10);
  @$pb.TagNumber(11)
  set editedAt($fixnum.Int64 v) { $_setInt64(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasEditedAt() => $_has(10);
  @$pb.TagNumber(11)
  void clearEditedAt() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get status => $_getIZ(11);
  @$pb.TagNumber(12)
  set status($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasStatus() => $_has(11);
  @$pb.TagNumber(12)
  void clearStatus() => clearField(12);

  @$pb.TagNumber(13)
  $core.String get replyToId => $_getSZ(12);
  @$pb.TagNumber(13)
  set replyToId($core.String v) { $_setString(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasReplyToId() => $_has(12);
  @$pb.TagNumber(13)
  void clearReplyToId() => clearField(13);

  @$pb.TagNumber(14)
  $core.String get replyPreview => $_getSZ(13);
  @$pb.TagNumber(14)
  set replyPreview($core.String v) { $_setString(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasReplyPreview() => $_has(13);
  @$pb.TagNumber(14)
  void clearReplyPreview() => clearField(14);

  @$pb.TagNumber(15)
  $core.String get forwardFrom => $_getSZ(14);
  @$pb.TagNumber(15)
  set forwardFrom($core.String v) { $_setString(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasForwardFrom() => $_has(14);
  @$pb.TagNumber(15)
  void clearForwardFrom() => clearField(15);

  @$pb.TagNumber(16)
  $core.bool get isPinned => $_getBF(15);
  @$pb.TagNumber(16)
  set isPinned($core.bool v) { $_setBool(15, v); }
  @$pb.TagNumber(16)
  $core.bool hasIsPinned() => $_has(15);
  @$pb.TagNumber(16)
  void clearIsPinned() => clearField(16);

  @$pb.TagNumber(17)
  $core.bool get hasMedia => $_getBF(16);
  @$pb.TagNumber(17)
  set hasMedia($core.bool v) { $_setBool(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasHasMedia() => $_has(16);
  @$pb.TagNumber(17)
  void clearHasMedia() => clearField(17);

  /// Media metadata (populated from media table join).
  @$pb.TagNumber(18)
  $core.int get mediaType => $_getIZ(17);
  @$pb.TagNumber(18)
  set mediaType($core.int v) { $_setSignedInt32(17, v); }
  @$pb.TagNumber(18)
  $core.bool hasMediaType() => $_has(17);
  @$pb.TagNumber(18)
  void clearMediaType() => clearField(18);

  @$pb.TagNumber(19)
  $core.String get mediaFileName => $_getSZ(18);
  @$pb.TagNumber(19)
  set mediaFileName($core.String v) { $_setString(18, v); }
  @$pb.TagNumber(19)
  $core.bool hasMediaFileName() => $_has(18);
  @$pb.TagNumber(19)
  void clearMediaFileName() => clearField(19);

  @$pb.TagNumber(20)
  $core.String get mediaMimeType => $_getSZ(19);
  @$pb.TagNumber(20)
  set mediaMimeType($core.String v) { $_setString(19, v); }
  @$pb.TagNumber(20)
  $core.bool hasMediaMimeType() => $_has(19);
  @$pb.TagNumber(20)
  void clearMediaMimeType() => clearField(20);

  @$pb.TagNumber(21)
  $fixnum.Int64 get mediaFileSize => $_getI64(20);
  @$pb.TagNumber(21)
  set mediaFileSize($fixnum.Int64 v) { $_setInt64(20, v); }
  @$pb.TagNumber(21)
  $core.bool hasMediaFileSize() => $_has(20);
  @$pb.TagNumber(21)
  void clearMediaFileSize() => clearField(21);

  @$pb.TagNumber(22)
  $core.String get mediaThumbB64 => $_getSZ(21);
  @$pb.TagNumber(22)
  set mediaThumbB64($core.String v) { $_setString(21, v); }
  @$pb.TagNumber(22)
  $core.bool hasMediaThumbB64() => $_has(21);
  @$pb.TagNumber(22)
  void clearMediaThumbB64() => clearField(22);

  @$pb.TagNumber(23)
  $core.String get mediaLocalPath => $_getSZ(22);
  @$pb.TagNumber(23)
  set mediaLocalPath($core.String v) { $_setString(22, v); }
  @$pb.TagNumber(23)
  $core.bool hasMediaLocalPath() => $_has(22);
  @$pb.TagNumber(23)
  void clearMediaLocalPath() => clearField(23);

  @$pb.TagNumber(24)
  $core.int get mediaWidth => $_getIZ(23);
  @$pb.TagNumber(24)
  set mediaWidth($core.int v) { $_setSignedInt32(23, v); }
  @$pb.TagNumber(24)
  $core.bool hasMediaWidth() => $_has(23);
  @$pb.TagNumber(24)
  void clearMediaWidth() => clearField(24);

  @$pb.TagNumber(25)
  $core.int get mediaHeight => $_getIZ(24);
  @$pb.TagNumber(25)
  set mediaHeight($core.int v) { $_setSignedInt32(24, v); }
  @$pb.TagNumber(25)
  $core.bool hasMediaHeight() => $_has(24);
  @$pb.TagNumber(25)
  void clearMediaHeight() => clearField(25);

  @$pb.TagNumber(26)
  $core.int get mediaDuration => $_getIZ(25);
  @$pb.TagNumber(26)
  set mediaDuration($core.int v) { $_setSignedInt32(25, v); }
  @$pb.TagNumber(26)
  $core.bool hasMediaDuration() => $_has(25);
  @$pb.TagNumber(26)
  void clearMediaDuration() => clearField(26);

  @$pb.TagNumber(27)
  $core.int get mediaDownloadState => $_getIZ(26);
  @$pb.TagNumber(27)
  set mediaDownloadState($core.int v) { $_setSignedInt32(26, v); }
  @$pb.TagNumber(27)
  $core.bool hasMediaDownloadState() => $_has(26);
  @$pb.TagNumber(27)
  void clearMediaDownloadState() => clearField(27);

  @$pb.TagNumber(28)
  $core.bool get isOutgoing => $_getBF(27);
  @$pb.TagNumber(28)
  set isOutgoing($core.bool v) { $_setBool(27, v); }
  @$pb.TagNumber(28)
  $core.bool hasIsOutgoing() => $_has(27);
  @$pb.TagNumber(28)
  void clearIsOutgoing() => clearField(28);

  @$pb.TagNumber(29)
  $core.String get senderRank => $_getSZ(28);
  @$pb.TagNumber(29)
  set senderRank($core.String v) { $_setString(28, v); }
  @$pb.TagNumber(29)
  $core.bool hasSenderRank() => $_has(28);
  @$pb.TagNumber(29)
  void clearSenderRank() => clearField(29);

  @$pb.TagNumber(30)
  $core.int get senderColorId => $_getIZ(29);
  @$pb.TagNumber(30)
  set senderColorId($core.int v) { $_setSignedInt32(29, v); }
  @$pb.TagNumber(30)
  $core.bool hasSenderColorId() => $_has(29);
  @$pb.TagNumber(30)
  void clearSenderColorId() => clearField(30);

  @$pb.TagNumber(31)
  $core.bool get isService => $_getBF(30);
  @$pb.TagNumber(31)
  set isService($core.bool v) { $_setBool(30, v); }
  @$pb.TagNumber(31)
  $core.bool hasIsService() => $_has(30);
  @$pb.TagNumber(31)
  void clearIsService() => clearField(31);

  @$pb.TagNumber(32)
  $core.String get groupedId => $_getSZ(31);
  @$pb.TagNumber(32)
  set groupedId($core.String v) { $_setString(31, v); }
  @$pb.TagNumber(32)
  $core.bool hasGroupedId() => $_has(31);
  @$pb.TagNumber(32)
  void clearGroupedId() => clearField(32);

  @$pb.TagNumber(33)
  $core.String get mediaRemoteRef => $_getSZ(32);
  @$pb.TagNumber(33)
  set mediaRemoteRef($core.String v) { $_setString(32, v); }
  @$pb.TagNumber(33)
  $core.bool hasMediaRemoteRef() => $_has(32);
  @$pb.TagNumber(33)
  void clearMediaRemoteRef() => clearField(33);

  @$pb.TagNumber(34)
  $core.String get mediaExtra => $_getSZ(33);
  @$pb.TagNumber(34)
  set mediaExtra($core.String v) { $_setString(33, v); }
  @$pb.TagNumber(34)
  $core.bool hasMediaExtra() => $_has(33);
  @$pb.TagNumber(34)
  void clearMediaExtra() => clearField(34);
}

class EngineGetMessagesRequest extends $pb.GeneratedMessage {
  factory EngineGetMessagesRequest({
    $core.String? accountId,
    $core.String? chatId,
    $fixnum.Int64? beforeMs,
    $core.int? limit,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (beforeMs != null) {
      $result.beforeMs = beforeMs;
    }
    if (limit != null) {
      $result.limit = limit;
    }
    return $result;
  }
  EngineGetMessagesRequest._() : super();
  factory EngineGetMessagesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetMessagesRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetMessagesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aInt64(3, _omitFieldNames ? '' : 'beforeMs')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetMessagesRequest clone() => EngineGetMessagesRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetMessagesRequest copyWith(void Function(EngineGetMessagesRequest) updates) => super.copyWith((message) => updates(message as EngineGetMessagesRequest)) as EngineGetMessagesRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetMessagesRequest create() => EngineGetMessagesRequest._();
  EngineGetMessagesRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetMessagesRequest> createRepeated() => $pb.PbList<EngineGetMessagesRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetMessagesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetMessagesRequest>(create);
  static EngineGetMessagesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get beforeMs => $_getI64(2);
  @$pb.TagNumber(3)
  set beforeMs($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasBeforeMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearBeforeMs() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get limit => $_getIZ(3);
  @$pb.TagNumber(4)
  set limit($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLimit() => $_has(3);
  @$pb.TagNumber(4)
  void clearLimit() => clearField(4);
}

class EngineGetMessagesResponse extends $pb.GeneratedMessage {
  factory EngineGetMessagesResponse({
    $core.Iterable<EngineCachedMessage>? messages,
  }) {
    final $result = create();
    if (messages != null) {
      $result.messages.addAll(messages);
    }
    return $result;
  }
  EngineGetMessagesResponse._() : super();
  factory EngineGetMessagesResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetMessagesResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetMessagesResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineCachedMessage>(1, _omitFieldNames ? '' : 'messages', $pb.PbFieldType.PM, subBuilder: EngineCachedMessage.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetMessagesResponse clone() => EngineGetMessagesResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetMessagesResponse copyWith(void Function(EngineGetMessagesResponse) updates) => super.copyWith((message) => updates(message as EngineGetMessagesResponse)) as EngineGetMessagesResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetMessagesResponse create() => EngineGetMessagesResponse._();
  EngineGetMessagesResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetMessagesResponse> createRepeated() => $pb.PbList<EngineGetMessagesResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetMessagesResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetMessagesResponse>(create);
  static EngineGetMessagesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineCachedMessage> get messages => $_getList(0);
}

class EngineSendMessageRequest extends $pb.GeneratedMessage {
  factory EngineSendMessageRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? text,
    $core.String? replyToId,
    $core.bool? silent,
    $fixnum.Int64? scheduleDate,
    $core.String? topicRootId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (text != null) {
      $result.text = text;
    }
    if (replyToId != null) {
      $result.replyToId = replyToId;
    }
    if (silent != null) {
      $result.silent = silent;
    }
    if (scheduleDate != null) {
      $result.scheduleDate = scheduleDate;
    }
    if (topicRootId != null) {
      $result.topicRootId = topicRootId;
    }
    return $result;
  }
  EngineSendMessageRequest._() : super();
  factory EngineSendMessageRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSendMessageRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSendMessageRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'text')
    ..aOS(4, _omitFieldNames ? '' : 'replyToId')
    ..aOB(5, _omitFieldNames ? '' : 'silent')
    ..aInt64(6, _omitFieldNames ? '' : 'scheduleDate')
    ..aOS(7, _omitFieldNames ? '' : 'topicRootId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSendMessageRequest clone() => EngineSendMessageRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSendMessageRequest copyWith(void Function(EngineSendMessageRequest) updates) => super.copyWith((message) => updates(message as EngineSendMessageRequest)) as EngineSendMessageRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSendMessageRequest create() => EngineSendMessageRequest._();
  EngineSendMessageRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSendMessageRequest> createRepeated() => $pb.PbList<EngineSendMessageRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSendMessageRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSendMessageRequest>(create);
  static EngineSendMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get text => $_getSZ(2);
  @$pb.TagNumber(3)
  set text($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasText() => $_has(2);
  @$pb.TagNumber(3)
  void clearText() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get replyToId => $_getSZ(3);
  @$pb.TagNumber(4)
  set replyToId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasReplyToId() => $_has(3);
  @$pb.TagNumber(4)
  void clearReplyToId() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get silent => $_getBF(4);
  @$pb.TagNumber(5)
  set silent($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSilent() => $_has(4);
  @$pb.TagNumber(5)
  void clearSilent() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get scheduleDate => $_getI64(5);
  @$pb.TagNumber(6)
  set scheduleDate($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasScheduleDate() => $_has(5);
  @$pb.TagNumber(6)
  void clearScheduleDate() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get topicRootId => $_getSZ(6);
  @$pb.TagNumber(7)
  set topicRootId($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTopicRootId() => $_has(6);
  @$pb.TagNumber(7)
  void clearTopicRootId() => clearField(7);
}

class EngineSendMessageResponse extends $pb.GeneratedMessage {
  factory EngineSendMessageResponse({
    $core.String? localId,
  }) {
    final $result = create();
    if (localId != null) {
      $result.localId = localId;
    }
    return $result;
  }
  EngineSendMessageResponse._() : super();
  factory EngineSendMessageResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSendMessageResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSendMessageResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'localId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSendMessageResponse clone() => EngineSendMessageResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSendMessageResponse copyWith(void Function(EngineSendMessageResponse) updates) => super.copyWith((message) => updates(message as EngineSendMessageResponse)) as EngineSendMessageResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSendMessageResponse create() => EngineSendMessageResponse._();
  EngineSendMessageResponse createEmptyInstance() => create();
  static $pb.PbList<EngineSendMessageResponse> createRepeated() => $pb.PbList<EngineSendMessageResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineSendMessageResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSendMessageResponse>(create);
  static EngineSendMessageResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get localId => $_getSZ(0);
  @$pb.TagNumber(1)
  set localId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLocalId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLocalId() => clearField(1);
}

class EngineEditMessageRequest extends $pb.GeneratedMessage {
  factory EngineEditMessageRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.String? newText,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (newText != null) {
      $result.newText = newText;
    }
    return $result;
  }
  EngineEditMessageRequest._() : super();
  factory EngineEditMessageRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineEditMessageRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineEditMessageRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..aOS(4, _omitFieldNames ? '' : 'newText')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineEditMessageRequest clone() => EngineEditMessageRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineEditMessageRequest copyWith(void Function(EngineEditMessageRequest) updates) => super.copyWith((message) => updates(message as EngineEditMessageRequest)) as EngineEditMessageRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineEditMessageRequest create() => EngineEditMessageRequest._();
  EngineEditMessageRequest createEmptyInstance() => create();
  static $pb.PbList<EngineEditMessageRequest> createRepeated() => $pb.PbList<EngineEditMessageRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineEditMessageRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineEditMessageRequest>(create);
  static EngineEditMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get newText => $_getSZ(3);
  @$pb.TagNumber(4)
  set newText($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasNewText() => $_has(3);
  @$pb.TagNumber(4)
  void clearNewText() => clearField(4);
}

class EngineDeleteMessageRequest extends $pb.GeneratedMessage {
  factory EngineDeleteMessageRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    return $result;
  }
  EngineDeleteMessageRequest._() : super();
  factory EngineDeleteMessageRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineDeleteMessageRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineDeleteMessageRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineDeleteMessageRequest clone() => EngineDeleteMessageRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineDeleteMessageRequest copyWith(void Function(EngineDeleteMessageRequest) updates) => super.copyWith((message) => updates(message as EngineDeleteMessageRequest)) as EngineDeleteMessageRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineDeleteMessageRequest create() => EngineDeleteMessageRequest._();
  EngineDeleteMessageRequest createEmptyInstance() => create();
  static $pb.PbList<EngineDeleteMessageRequest> createRepeated() => $pb.PbList<EngineDeleteMessageRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineDeleteMessageRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineDeleteMessageRequest>(create);
  static EngineDeleteMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);
}

class EngineJoinChatRequest extends $pb.GeneratedMessage {
  factory EngineJoinChatRequest({
    $core.String? accountId,
    $core.String? channelName,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (channelName != null) {
      $result.channelName = channelName;
    }
    return $result;
  }
  EngineJoinChatRequest._() : super();
  factory EngineJoinChatRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineJoinChatRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineJoinChatRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'channelName')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineJoinChatRequest clone() => EngineJoinChatRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineJoinChatRequest copyWith(void Function(EngineJoinChatRequest) updates) => super.copyWith((message) => updates(message as EngineJoinChatRequest)) as EngineJoinChatRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineJoinChatRequest create() => EngineJoinChatRequest._();
  EngineJoinChatRequest createEmptyInstance() => create();
  static $pb.PbList<EngineJoinChatRequest> createRepeated() => $pb.PbList<EngineJoinChatRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineJoinChatRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineJoinChatRequest>(create);
  static EngineJoinChatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get channelName => $_getSZ(1);
  @$pb.TagNumber(2)
  set channelName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChannelName() => $_has(1);
  @$pb.TagNumber(2)
  void clearChannelName() => clearField(2);
}

class EngineLeaveChatRequest extends $pb.GeneratedMessage {
  factory EngineLeaveChatRequest({
    $core.String? accountId,
    $core.String? chatId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  EngineLeaveChatRequest._() : super();
  factory EngineLeaveChatRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineLeaveChatRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineLeaveChatRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineLeaveChatRequest clone() => EngineLeaveChatRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineLeaveChatRequest copyWith(void Function(EngineLeaveChatRequest) updates) => super.copyWith((message) => updates(message as EngineLeaveChatRequest)) as EngineLeaveChatRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineLeaveChatRequest create() => EngineLeaveChatRequest._();
  EngineLeaveChatRequest createEmptyInstance() => create();
  static $pb.PbList<EngineLeaveChatRequest> createRepeated() => $pb.PbList<EngineLeaveChatRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineLeaveChatRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineLeaveChatRequest>(create);
  static EngineLeaveChatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class EngineForwardMessageRequest extends $pb.GeneratedMessage {
  factory EngineForwardMessageRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.String? toChatId,
    $core.bool? dropAuthor,
    $core.bool? dropCaptions,
    $core.bool? silent,
    $fixnum.Int64? scheduleDate,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (toChatId != null) {
      $result.toChatId = toChatId;
    }
    if (dropAuthor != null) {
      $result.dropAuthor = dropAuthor;
    }
    if (dropCaptions != null) {
      $result.dropCaptions = dropCaptions;
    }
    if (silent != null) {
      $result.silent = silent;
    }
    if (scheduleDate != null) {
      $result.scheduleDate = scheduleDate;
    }
    return $result;
  }
  EngineForwardMessageRequest._() : super();
  factory EngineForwardMessageRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineForwardMessageRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineForwardMessageRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..aOS(4, _omitFieldNames ? '' : 'toChatId')
    ..aOB(5, _omitFieldNames ? '' : 'dropAuthor')
    ..aOB(6, _omitFieldNames ? '' : 'dropCaptions')
    ..aOB(7, _omitFieldNames ? '' : 'silent')
    ..aInt64(8, _omitFieldNames ? '' : 'scheduleDate')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineForwardMessageRequest clone() => EngineForwardMessageRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineForwardMessageRequest copyWith(void Function(EngineForwardMessageRequest) updates) => super.copyWith((message) => updates(message as EngineForwardMessageRequest)) as EngineForwardMessageRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineForwardMessageRequest create() => EngineForwardMessageRequest._();
  EngineForwardMessageRequest createEmptyInstance() => create();
  static $pb.PbList<EngineForwardMessageRequest> createRepeated() => $pb.PbList<EngineForwardMessageRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineForwardMessageRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineForwardMessageRequest>(create);
  static EngineForwardMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get toChatId => $_getSZ(3);
  @$pb.TagNumber(4)
  set toChatId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasToChatId() => $_has(3);
  @$pb.TagNumber(4)
  void clearToChatId() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get dropAuthor => $_getBF(4);
  @$pb.TagNumber(5)
  set dropAuthor($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDropAuthor() => $_has(4);
  @$pb.TagNumber(5)
  void clearDropAuthor() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get dropCaptions => $_getBF(5);
  @$pb.TagNumber(6)
  set dropCaptions($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasDropCaptions() => $_has(5);
  @$pb.TagNumber(6)
  void clearDropCaptions() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get silent => $_getBF(6);
  @$pb.TagNumber(7)
  set silent($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSilent() => $_has(6);
  @$pb.TagNumber(7)
  void clearSilent() => clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get scheduleDate => $_getI64(7);
  @$pb.TagNumber(8)
  set scheduleDate($fixnum.Int64 v) { $_setInt64(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasScheduleDate() => $_has(7);
  @$pb.TagNumber(8)
  void clearScheduleDate() => clearField(8);
}

class EngineReactToMessageRequest extends $pb.GeneratedMessage {
  factory EngineReactToMessageRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.String? emoji,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (emoji != null) {
      $result.emoji = emoji;
    }
    return $result;
  }
  EngineReactToMessageRequest._() : super();
  factory EngineReactToMessageRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineReactToMessageRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineReactToMessageRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..aOS(4, _omitFieldNames ? '' : 'emoji')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineReactToMessageRequest clone() => EngineReactToMessageRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineReactToMessageRequest copyWith(void Function(EngineReactToMessageRequest) updates) => super.copyWith((message) => updates(message as EngineReactToMessageRequest)) as EngineReactToMessageRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineReactToMessageRequest create() => EngineReactToMessageRequest._();
  EngineReactToMessageRequest createEmptyInstance() => create();
  static $pb.PbList<EngineReactToMessageRequest> createRepeated() => $pb.PbList<EngineReactToMessageRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineReactToMessageRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineReactToMessageRequest>(create);
  static EngineReactToMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get emoji => $_getSZ(3);
  @$pb.TagNumber(4)
  set emoji($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasEmoji() => $_has(3);
  @$pb.TagNumber(4)
  void clearEmoji() => clearField(4);
}

class EnginePinMessageRequest extends $pb.GeneratedMessage {
  factory EnginePinMessageRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.bool? pinned,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (pinned != null) {
      $result.pinned = pinned;
    }
    return $result;
  }
  EnginePinMessageRequest._() : super();
  factory EnginePinMessageRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EnginePinMessageRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EnginePinMessageRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..aOB(4, _omitFieldNames ? '' : 'pinned')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EnginePinMessageRequest clone() => EnginePinMessageRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EnginePinMessageRequest copyWith(void Function(EnginePinMessageRequest) updates) => super.copyWith((message) => updates(message as EnginePinMessageRequest)) as EnginePinMessageRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EnginePinMessageRequest create() => EnginePinMessageRequest._();
  EnginePinMessageRequest createEmptyInstance() => create();
  static $pb.PbList<EnginePinMessageRequest> createRepeated() => $pb.PbList<EnginePinMessageRequest>();
  @$core.pragma('dart2js:noInline')
  static EnginePinMessageRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EnginePinMessageRequest>(create);
  static EnginePinMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get pinned => $_getBF(3);
  @$pb.TagNumber(4)
  set pinned($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPinned() => $_has(3);
  @$pb.TagNumber(4)
  void clearPinned() => clearField(4);
}

class EngineUploadFileRequest extends $pb.GeneratedMessage {
  factory EngineUploadFileRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? filePath,
    $core.String? caption,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (filePath != null) {
      $result.filePath = filePath;
    }
    if (caption != null) {
      $result.caption = caption;
    }
    return $result;
  }
  EngineUploadFileRequest._() : super();
  factory EngineUploadFileRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineUploadFileRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineUploadFileRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'filePath')
    ..aOS(4, _omitFieldNames ? '' : 'caption')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineUploadFileRequest clone() => EngineUploadFileRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineUploadFileRequest copyWith(void Function(EngineUploadFileRequest) updates) => super.copyWith((message) => updates(message as EngineUploadFileRequest)) as EngineUploadFileRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineUploadFileRequest create() => EngineUploadFileRequest._();
  EngineUploadFileRequest createEmptyInstance() => create();
  static $pb.PbList<EngineUploadFileRequest> createRepeated() => $pb.PbList<EngineUploadFileRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineUploadFileRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineUploadFileRequest>(create);
  static EngineUploadFileRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get filePath => $_getSZ(2);
  @$pb.TagNumber(3)
  set filePath($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFilePath() => $_has(2);
  @$pb.TagNumber(3)
  void clearFilePath() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get caption => $_getSZ(3);
  @$pb.TagNumber(4)
  set caption($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCaption() => $_has(3);
  @$pb.TagNumber(4)
  void clearCaption() => clearField(4);
}

class EngineUploadFileResponse extends $pb.GeneratedMessage {
  factory EngineUploadFileResponse({
    $core.String? msgId,
  }) {
    final $result = create();
    if (msgId != null) {
      $result.msgId = msgId;
    }
    return $result;
  }
  EngineUploadFileResponse._() : super();
  factory EngineUploadFileResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineUploadFileResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineUploadFileResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'msgId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineUploadFileResponse clone() => EngineUploadFileResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineUploadFileResponse copyWith(void Function(EngineUploadFileResponse) updates) => super.copyWith((message) => updates(message as EngineUploadFileResponse)) as EngineUploadFileResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineUploadFileResponse create() => EngineUploadFileResponse._();
  EngineUploadFileResponse createEmptyInstance() => create();
  static $pb.PbList<EngineUploadFileResponse> createRepeated() => $pb.PbList<EngineUploadFileResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineUploadFileResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineUploadFileResponse>(create);
  static EngineUploadFileResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get msgId => $_getSZ(0);
  @$pb.TagNumber(1)
  set msgId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMsgId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMsgId() => clearField(1);
}

class EngineRetryPendingRequest extends $pb.GeneratedMessage {
  factory EngineRetryPendingRequest({
    $core.String? localId,
  }) {
    final $result = create();
    if (localId != null) {
      $result.localId = localId;
    }
    return $result;
  }
  EngineRetryPendingRequest._() : super();
  factory EngineRetryPendingRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineRetryPendingRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineRetryPendingRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'localId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineRetryPendingRequest clone() => EngineRetryPendingRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineRetryPendingRequest copyWith(void Function(EngineRetryPendingRequest) updates) => super.copyWith((message) => updates(message as EngineRetryPendingRequest)) as EngineRetryPendingRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineRetryPendingRequest create() => EngineRetryPendingRequest._();
  EngineRetryPendingRequest createEmptyInstance() => create();
  static $pb.PbList<EngineRetryPendingRequest> createRepeated() => $pb.PbList<EngineRetryPendingRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineRetryPendingRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineRetryPendingRequest>(create);
  static EngineRetryPendingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get localId => $_getSZ(0);
  @$pb.TagNumber(1)
  set localId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLocalId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLocalId() => clearField(1);
}

class EngineGetMessageRawRequest extends $pb.GeneratedMessage {
  factory EngineGetMessageRawRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    return $result;
  }
  EngineGetMessageRawRequest._() : super();
  factory EngineGetMessageRawRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetMessageRawRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetMessageRawRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetMessageRawRequest clone() => EngineGetMessageRawRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetMessageRawRequest copyWith(void Function(EngineGetMessageRawRequest) updates) => super.copyWith((message) => updates(message as EngineGetMessageRawRequest)) as EngineGetMessageRawRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetMessageRawRequest create() => EngineGetMessageRawRequest._();
  EngineGetMessageRawRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetMessageRawRequest> createRepeated() => $pb.PbList<EngineGetMessageRawRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetMessageRawRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetMessageRawRequest>(create);
  static EngineGetMessageRawRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);
}

class EngineGetMessageRawResponse extends $pb.GeneratedMessage {
  factory EngineGetMessageRawResponse({
    $core.List<$core.int>? contentRaw,
  }) {
    final $result = create();
    if (contentRaw != null) {
      $result.contentRaw = contentRaw;
    }
    return $result;
  }
  EngineGetMessageRawResponse._() : super();
  factory EngineGetMessageRawResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetMessageRawResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetMessageRawResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..a<$core.List<$core.int>>(1, _omitFieldNames ? '' : 'contentRaw', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetMessageRawResponse clone() => EngineGetMessageRawResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetMessageRawResponse copyWith(void Function(EngineGetMessageRawResponse) updates) => super.copyWith((message) => updates(message as EngineGetMessageRawResponse)) as EngineGetMessageRawResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetMessageRawResponse create() => EngineGetMessageRawResponse._();
  EngineGetMessageRawResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetMessageRawResponse> createRepeated() => $pb.PbList<EngineGetMessageRawResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetMessageRawResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetMessageRawResponse>(create);
  static EngineGetMessageRawResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get contentRaw => $_getN(0);
  @$pb.TagNumber(1)
  set contentRaw($core.List<$core.int> v) { $_setBytes(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasContentRaw() => $_has(0);
  @$pb.TagNumber(1)
  void clearContentRaw() => clearField(1);
}

class EngineMemberInfo extends $pb.GeneratedMessage {
  factory EngineMemberInfo({
    $core.String? userId,
    $core.String? username,
    $core.String? displayName,
    $core.String? avatarB64,
    $core.bool? isBot,
    $core.bool? isOnline,
    $core.String? role,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
    }
    if (username != null) {
      $result.username = username;
    }
    if (displayName != null) {
      $result.displayName = displayName;
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
    if (role != null) {
      $result.role = role;
    }
    return $result;
  }
  EngineMemberInfo._() : super();
  factory EngineMemberInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineMemberInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineMemberInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'displayName')
    ..aOS(4, _omitFieldNames ? '' : 'avatarB64')
    ..aOB(5, _omitFieldNames ? '' : 'isBot')
    ..aOB(6, _omitFieldNames ? '' : 'isOnline')
    ..aOS(7, _omitFieldNames ? '' : 'role')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineMemberInfo clone() => EngineMemberInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineMemberInfo copyWith(void Function(EngineMemberInfo) updates) => super.copyWith((message) => updates(message as EngineMemberInfo)) as EngineMemberInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineMemberInfo create() => EngineMemberInfo._();
  EngineMemberInfo createEmptyInstance() => create();
  static $pb.PbList<EngineMemberInfo> createRepeated() => $pb.PbList<EngineMemberInfo>();
  @$core.pragma('dart2js:noInline')
  static EngineMemberInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineMemberInfo>(create);
  static EngineMemberInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

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
  $core.String get avatarB64 => $_getSZ(3);
  @$pb.TagNumber(4)
  set avatarB64($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAvatarB64() => $_has(3);
  @$pb.TagNumber(4)
  void clearAvatarB64() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get isBot => $_getBF(4);
  @$pb.TagNumber(5)
  set isBot($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasIsBot() => $_has(4);
  @$pb.TagNumber(5)
  void clearIsBot() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get isOnline => $_getBF(5);
  @$pb.TagNumber(6)
  set isOnline($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasIsOnline() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsOnline() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get role => $_getSZ(6);
  @$pb.TagNumber(7)
  set role($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasRole() => $_has(6);
  @$pb.TagNumber(7)
  void clearRole() => clearField(7);
}

class EngineGetChatMembersRequest extends $pb.GeneratedMessage {
  factory EngineGetChatMembersRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.int? limit,
    $core.int? offset,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (limit != null) {
      $result.limit = limit;
    }
    if (offset != null) {
      $result.offset = offset;
    }
    return $result;
  }
  EngineGetChatMembersRequest._() : super();
  factory EngineGetChatMembersRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetChatMembersRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetChatMembersRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'offset', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetChatMembersRequest clone() => EngineGetChatMembersRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetChatMembersRequest copyWith(void Function(EngineGetChatMembersRequest) updates) => super.copyWith((message) => updates(message as EngineGetChatMembersRequest)) as EngineGetChatMembersRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetChatMembersRequest create() => EngineGetChatMembersRequest._();
  EngineGetChatMembersRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetChatMembersRequest> createRepeated() => $pb.PbList<EngineGetChatMembersRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetChatMembersRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetChatMembersRequest>(create);
  static EngineGetChatMembersRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get limit => $_getIZ(2);
  @$pb.TagNumber(3)
  set limit($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLimit() => $_has(2);
  @$pb.TagNumber(3)
  void clearLimit() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get offset => $_getIZ(3);
  @$pb.TagNumber(4)
  set offset($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOffset() => $_has(3);
  @$pb.TagNumber(4)
  void clearOffset() => clearField(4);
}

class EngineGetChatMembersResponse extends $pb.GeneratedMessage {
  factory EngineGetChatMembersResponse({
    $core.Iterable<EngineMemberInfo>? members,
  }) {
    final $result = create();
    if (members != null) {
      $result.members.addAll(members);
    }
    return $result;
  }
  EngineGetChatMembersResponse._() : super();
  factory EngineGetChatMembersResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetChatMembersResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetChatMembersResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineMemberInfo>(1, _omitFieldNames ? '' : 'members', $pb.PbFieldType.PM, subBuilder: EngineMemberInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetChatMembersResponse clone() => EngineGetChatMembersResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetChatMembersResponse copyWith(void Function(EngineGetChatMembersResponse) updates) => super.copyWith((message) => updates(message as EngineGetChatMembersResponse)) as EngineGetChatMembersResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetChatMembersResponse create() => EngineGetChatMembersResponse._();
  EngineGetChatMembersResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetChatMembersResponse> createRepeated() => $pb.PbList<EngineGetChatMembersResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetChatMembersResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetChatMembersResponse>(create);
  static EngineGetChatMembersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineMemberInfo> get members => $_getList(0);
}

class EngineSetActiveChatRequest extends $pb.GeneratedMessage {
  factory EngineSetActiveChatRequest({
    $core.String? accountId,
    $core.String? chatId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  EngineSetActiveChatRequest._() : super();
  factory EngineSetActiveChatRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSetActiveChatRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSetActiveChatRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSetActiveChatRequest clone() => EngineSetActiveChatRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSetActiveChatRequest copyWith(void Function(EngineSetActiveChatRequest) updates) => super.copyWith((message) => updates(message as EngineSetActiveChatRequest)) as EngineSetActiveChatRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSetActiveChatRequest create() => EngineSetActiveChatRequest._();
  EngineSetActiveChatRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSetActiveChatRequest> createRepeated() => $pb.PbList<EngineSetActiveChatRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSetActiveChatRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSetActiveChatRequest>(create);
  static EngineSetActiveChatRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class EngineSearchResult extends $pb.GeneratedMessage {
  factory EngineSearchResult({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.String? senderName,
    $core.String? text,
    $fixnum.Int64? timestamp,
    $core.String? chatTitle,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (senderName != null) {
      $result.senderName = senderName;
    }
    if (text != null) {
      $result.text = text;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (chatTitle != null) {
      $result.chatTitle = chatTitle;
    }
    return $result;
  }
  EngineSearchResult._() : super();
  factory EngineSearchResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSearchResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSearchResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..aOS(4, _omitFieldNames ? '' : 'senderName')
    ..aOS(5, _omitFieldNames ? '' : 'text')
    ..aInt64(6, _omitFieldNames ? '' : 'timestamp')
    ..aOS(7, _omitFieldNames ? '' : 'chatTitle')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSearchResult clone() => EngineSearchResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSearchResult copyWith(void Function(EngineSearchResult) updates) => super.copyWith((message) => updates(message as EngineSearchResult)) as EngineSearchResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSearchResult create() => EngineSearchResult._();
  EngineSearchResult createEmptyInstance() => create();
  static $pb.PbList<EngineSearchResult> createRepeated() => $pb.PbList<EngineSearchResult>();
  @$core.pragma('dart2js:noInline')
  static EngineSearchResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSearchResult>(create);
  static EngineSearchResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

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
  $fixnum.Int64 get timestamp => $_getI64(5);
  @$pb.TagNumber(6)
  set timestamp($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTimestamp() => $_has(5);
  @$pb.TagNumber(6)
  void clearTimestamp() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get chatTitle => $_getSZ(6);
  @$pb.TagNumber(7)
  set chatTitle($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasChatTitle() => $_has(6);
  @$pb.TagNumber(7)
  void clearChatTitle() => clearField(7);
}

class EngineSearchMessagesRequest extends $pb.GeneratedMessage {
  factory EngineSearchMessagesRequest({
    $core.String? query,
    $core.String? accountId,
    $core.int? limit,
  }) {
    final $result = create();
    if (query != null) {
      $result.query = query;
    }
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (limit != null) {
      $result.limit = limit;
    }
    return $result;
  }
  EngineSearchMessagesRequest._() : super();
  factory EngineSearchMessagesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSearchMessagesRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSearchMessagesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'query')
    ..aOS(2, _omitFieldNames ? '' : 'accountId')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSearchMessagesRequest clone() => EngineSearchMessagesRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSearchMessagesRequest copyWith(void Function(EngineSearchMessagesRequest) updates) => super.copyWith((message) => updates(message as EngineSearchMessagesRequest)) as EngineSearchMessagesRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSearchMessagesRequest create() => EngineSearchMessagesRequest._();
  EngineSearchMessagesRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSearchMessagesRequest> createRepeated() => $pb.PbList<EngineSearchMessagesRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSearchMessagesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSearchMessagesRequest>(create);
  static EngineSearchMessagesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get query => $_getSZ(0);
  @$pb.TagNumber(1)
  set query($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get accountId => $_getSZ(1);
  @$pb.TagNumber(2)
  set accountId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccountId() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccountId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get limit => $_getIZ(2);
  @$pb.TagNumber(3)
  set limit($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLimit() => $_has(2);
  @$pb.TagNumber(3)
  void clearLimit() => clearField(3);
}

class EngineSearchMessagesResponse extends $pb.GeneratedMessage {
  factory EngineSearchMessagesResponse({
    $core.Iterable<EngineSearchResult>? results,
  }) {
    final $result = create();
    if (results != null) {
      $result.results.addAll(results);
    }
    return $result;
  }
  EngineSearchMessagesResponse._() : super();
  factory EngineSearchMessagesResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSearchMessagesResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSearchMessagesResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineSearchResult>(1, _omitFieldNames ? '' : 'results', $pb.PbFieldType.PM, subBuilder: EngineSearchResult.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSearchMessagesResponse clone() => EngineSearchMessagesResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSearchMessagesResponse copyWith(void Function(EngineSearchMessagesResponse) updates) => super.copyWith((message) => updates(message as EngineSearchMessagesResponse)) as EngineSearchMessagesResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSearchMessagesResponse create() => EngineSearchMessagesResponse._();
  EngineSearchMessagesResponse createEmptyInstance() => create();
  static $pb.PbList<EngineSearchMessagesResponse> createRepeated() => $pb.PbList<EngineSearchMessagesResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineSearchMessagesResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSearchMessagesResponse>(create);
  static EngineSearchMessagesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineSearchResult> get results => $_getList(0);
}

class EngineSearchChatsRequest extends $pb.GeneratedMessage {
  factory EngineSearchChatsRequest({
    $core.String? query,
    $core.int? limit,
  }) {
    final $result = create();
    if (query != null) {
      $result.query = query;
    }
    if (limit != null) {
      $result.limit = limit;
    }
    return $result;
  }
  EngineSearchChatsRequest._() : super();
  factory EngineSearchChatsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSearchChatsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSearchChatsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'query')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSearchChatsRequest clone() => EngineSearchChatsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSearchChatsRequest copyWith(void Function(EngineSearchChatsRequest) updates) => super.copyWith((message) => updates(message as EngineSearchChatsRequest)) as EngineSearchChatsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSearchChatsRequest create() => EngineSearchChatsRequest._();
  EngineSearchChatsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSearchChatsRequest> createRepeated() => $pb.PbList<EngineSearchChatsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSearchChatsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSearchChatsRequest>(create);
  static EngineSearchChatsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get query => $_getSZ(0);
  @$pb.TagNumber(1)
  set query($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasQuery() => $_has(0);
  @$pb.TagNumber(1)
  void clearQuery() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLimit() => $_has(1);
  @$pb.TagNumber(2)
  void clearLimit() => clearField(2);
}

class EngineSearchChatsResponse extends $pb.GeneratedMessage {
  factory EngineSearchChatsResponse({
    $core.Iterable<EngineChatInfo>? chats,
  }) {
    final $result = create();
    if (chats != null) {
      $result.chats.addAll(chats);
    }
    return $result;
  }
  EngineSearchChatsResponse._() : super();
  factory EngineSearchChatsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSearchChatsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSearchChatsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineChatInfo>(1, _omitFieldNames ? '' : 'chats', $pb.PbFieldType.PM, subBuilder: EngineChatInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSearchChatsResponse clone() => EngineSearchChatsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSearchChatsResponse copyWith(void Function(EngineSearchChatsResponse) updates) => super.copyWith((message) => updates(message as EngineSearchChatsResponse)) as EngineSearchChatsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSearchChatsResponse create() => EngineSearchChatsResponse._();
  EngineSearchChatsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineSearchChatsResponse> createRepeated() => $pb.PbList<EngineSearchChatsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineSearchChatsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSearchChatsResponse>(create);
  static EngineSearchChatsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineChatInfo> get chats => $_getList(0);
}

class EngineRequestDownloadRequest extends $pb.GeneratedMessage {
  factory EngineRequestDownloadRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.int? seq,
    $core.int? priority,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (seq != null) {
      $result.seq = seq;
    }
    if (priority != null) {
      $result.priority = priority;
    }
    return $result;
  }
  EngineRequestDownloadRequest._() : super();
  factory EngineRequestDownloadRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineRequestDownloadRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineRequestDownloadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'priority', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineRequestDownloadRequest clone() => EngineRequestDownloadRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineRequestDownloadRequest copyWith(void Function(EngineRequestDownloadRequest) updates) => super.copyWith((message) => updates(message as EngineRequestDownloadRequest)) as EngineRequestDownloadRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineRequestDownloadRequest create() => EngineRequestDownloadRequest._();
  EngineRequestDownloadRequest createEmptyInstance() => create();
  static $pb.PbList<EngineRequestDownloadRequest> createRepeated() => $pb.PbList<EngineRequestDownloadRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineRequestDownloadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineRequestDownloadRequest>(create);
  static EngineRequestDownloadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get seq => $_getIZ(3);
  @$pb.TagNumber(4)
  set seq($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSeq() => $_has(3);
  @$pb.TagNumber(4)
  void clearSeq() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get priority => $_getIZ(4);
  @$pb.TagNumber(5)
  set priority($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasPriority() => $_has(4);
  @$pb.TagNumber(5)
  void clearPriority() => clearField(5);
}

class EngineCancelDownloadRequest extends $pb.GeneratedMessage {
  factory EngineCancelDownloadRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.int? seq,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (seq != null) {
      $result.seq = seq;
    }
    return $result;
  }
  EngineCancelDownloadRequest._() : super();
  factory EngineCancelDownloadRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineCancelDownloadRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCancelDownloadRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineCancelDownloadRequest clone() => EngineCancelDownloadRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineCancelDownloadRequest copyWith(void Function(EngineCancelDownloadRequest) updates) => super.copyWith((message) => updates(message as EngineCancelDownloadRequest)) as EngineCancelDownloadRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineCancelDownloadRequest create() => EngineCancelDownloadRequest._();
  EngineCancelDownloadRequest createEmptyInstance() => create();
  static $pb.PbList<EngineCancelDownloadRequest> createRepeated() => $pb.PbList<EngineCancelDownloadRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineCancelDownloadRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCancelDownloadRequest>(create);
  static EngineCancelDownloadRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get seq => $_getIZ(3);
  @$pb.TagNumber(4)
  set seq($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSeq() => $_has(3);
  @$pb.TagNumber(4)
  void clearSeq() => clearField(4);
}

class EngineGetCacheSizeResponse extends $pb.GeneratedMessage {
  factory EngineGetCacheSizeResponse({
    $fixnum.Int64? sizeBytes,
  }) {
    final $result = create();
    if (sizeBytes != null) {
      $result.sizeBytes = sizeBytes;
    }
    return $result;
  }
  EngineGetCacheSizeResponse._() : super();
  factory EngineGetCacheSizeResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetCacheSizeResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetCacheSizeResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'sizeBytes')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetCacheSizeResponse clone() => EngineGetCacheSizeResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetCacheSizeResponse copyWith(void Function(EngineGetCacheSizeResponse) updates) => super.copyWith((message) => updates(message as EngineGetCacheSizeResponse)) as EngineGetCacheSizeResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetCacheSizeResponse create() => EngineGetCacheSizeResponse._();
  EngineGetCacheSizeResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetCacheSizeResponse> createRepeated() => $pb.PbList<EngineGetCacheSizeResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetCacheSizeResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetCacheSizeResponse>(create);
  static EngineGetCacheSizeResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get sizeBytes => $_getI64(0);
  @$pb.TagNumber(1)
  set sizeBytes($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSizeBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearSizeBytes() => clearField(1);
}

class EngineClearCacheRequest extends $pb.GeneratedMessage {
  factory EngineClearCacheRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineClearCacheRequest._() : super();
  factory EngineClearCacheRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineClearCacheRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineClearCacheRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineClearCacheRequest clone() => EngineClearCacheRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineClearCacheRequest copyWith(void Function(EngineClearCacheRequest) updates) => super.copyWith((message) => updates(message as EngineClearCacheRequest)) as EngineClearCacheRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineClearCacheRequest create() => EngineClearCacheRequest._();
  EngineClearCacheRequest createEmptyInstance() => create();
  static $pb.PbList<EngineClearCacheRequest> createRepeated() => $pb.PbList<EngineClearCacheRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineClearCacheRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineClearCacheRequest>(create);
  static EngineClearCacheRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class EngineGetSharedMediaRequest extends $pb.GeneratedMessage {
  factory EngineGetSharedMediaRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? mediaType,
    $core.int? limit,
    $core.int? offset,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (mediaType != null) {
      $result.mediaType = mediaType;
    }
    if (limit != null) {
      $result.limit = limit;
    }
    if (offset != null) {
      $result.offset = offset;
    }
    return $result;
  }
  EngineGetSharedMediaRequest._() : super();
  factory EngineGetSharedMediaRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetSharedMediaRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSharedMediaRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'mediaType')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'offset', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetSharedMediaRequest clone() => EngineGetSharedMediaRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetSharedMediaRequest copyWith(void Function(EngineGetSharedMediaRequest) updates) => super.copyWith((message) => updates(message as EngineGetSharedMediaRequest)) as EngineGetSharedMediaRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSharedMediaRequest create() => EngineGetSharedMediaRequest._();
  EngineGetSharedMediaRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetSharedMediaRequest> createRepeated() => $pb.PbList<EngineGetSharedMediaRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSharedMediaRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSharedMediaRequest>(create);
  static EngineGetSharedMediaRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get mediaType => $_getSZ(2);
  @$pb.TagNumber(3)
  set mediaType($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMediaType() => $_has(2);
  @$pb.TagNumber(3)
  void clearMediaType() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get limit => $_getIZ(3);
  @$pb.TagNumber(4)
  set limit($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLimit() => $_has(3);
  @$pb.TagNumber(4)
  void clearLimit() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get offset => $_getIZ(4);
  @$pb.TagNumber(5)
  set offset($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasOffset() => $_has(4);
  @$pb.TagNumber(5)
  void clearOffset() => clearField(5);
}

class EngineSharedMediaItem extends $pb.GeneratedMessage {
  factory EngineSharedMediaItem({
    $core.String? msgId,
    $fixnum.Int64? timestamp,
    $core.int? mediaType,
    $core.String? fileName,
    $core.String? mimeType,
    $fixnum.Int64? fileSize,
    $core.String? thumbB64,
    $core.String? localPath,
    $core.int? width,
    $core.int? height,
    $core.int? duration,
  }) {
    final $result = create();
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (timestamp != null) {
      $result.timestamp = timestamp;
    }
    if (mediaType != null) {
      $result.mediaType = mediaType;
    }
    if (fileName != null) {
      $result.fileName = fileName;
    }
    if (mimeType != null) {
      $result.mimeType = mimeType;
    }
    if (fileSize != null) {
      $result.fileSize = fileSize;
    }
    if (thumbB64 != null) {
      $result.thumbB64 = thumbB64;
    }
    if (localPath != null) {
      $result.localPath = localPath;
    }
    if (width != null) {
      $result.width = width;
    }
    if (height != null) {
      $result.height = height;
    }
    if (duration != null) {
      $result.duration = duration;
    }
    return $result;
  }
  EngineSharedMediaItem._() : super();
  factory EngineSharedMediaItem.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSharedMediaItem.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSharedMediaItem', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'msgId')
    ..aInt64(2, _omitFieldNames ? '' : 'timestamp')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'mediaType', $pb.PbFieldType.O3)
    ..aOS(4, _omitFieldNames ? '' : 'fileName')
    ..aOS(5, _omitFieldNames ? '' : 'mimeType')
    ..aInt64(6, _omitFieldNames ? '' : 'fileSize')
    ..aOS(7, _omitFieldNames ? '' : 'thumbB64')
    ..aOS(8, _omitFieldNames ? '' : 'localPath')
    ..a<$core.int>(9, _omitFieldNames ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'height', $pb.PbFieldType.O3)
    ..a<$core.int>(11, _omitFieldNames ? '' : 'duration', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSharedMediaItem clone() => EngineSharedMediaItem()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSharedMediaItem copyWith(void Function(EngineSharedMediaItem) updates) => super.copyWith((message) => updates(message as EngineSharedMediaItem)) as EngineSharedMediaItem;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSharedMediaItem create() => EngineSharedMediaItem._();
  EngineSharedMediaItem createEmptyInstance() => create();
  static $pb.PbList<EngineSharedMediaItem> createRepeated() => $pb.PbList<EngineSharedMediaItem>();
  @$core.pragma('dart2js:noInline')
  static EngineSharedMediaItem getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSharedMediaItem>(create);
  static EngineSharedMediaItem? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get msgId => $_getSZ(0);
  @$pb.TagNumber(1)
  set msgId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMsgId() => $_has(0);
  @$pb.TagNumber(1)
  void clearMsgId() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestamp => $_getI64(1);
  @$pb.TagNumber(2)
  set timestamp($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestamp() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestamp() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get mediaType => $_getIZ(2);
  @$pb.TagNumber(3)
  set mediaType($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMediaType() => $_has(2);
  @$pb.TagNumber(3)
  void clearMediaType() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get fileName => $_getSZ(3);
  @$pb.TagNumber(4)
  set fileName($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasFileName() => $_has(3);
  @$pb.TagNumber(4)
  void clearFileName() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get mimeType => $_getSZ(4);
  @$pb.TagNumber(5)
  set mimeType($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMimeType() => $_has(4);
  @$pb.TagNumber(5)
  void clearMimeType() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get fileSize => $_getI64(5);
  @$pb.TagNumber(6)
  set fileSize($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasFileSize() => $_has(5);
  @$pb.TagNumber(6)
  void clearFileSize() => clearField(6);

  @$pb.TagNumber(7)
  $core.String get thumbB64 => $_getSZ(6);
  @$pb.TagNumber(7)
  set thumbB64($core.String v) { $_setString(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasThumbB64() => $_has(6);
  @$pb.TagNumber(7)
  void clearThumbB64() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get localPath => $_getSZ(7);
  @$pb.TagNumber(8)
  set localPath($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasLocalPath() => $_has(7);
  @$pb.TagNumber(8)
  void clearLocalPath() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get width => $_getIZ(8);
  @$pb.TagNumber(9)
  set width($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasWidth() => $_has(8);
  @$pb.TagNumber(9)
  void clearWidth() => clearField(9);

  @$pb.TagNumber(10)
  $core.int get height => $_getIZ(9);
  @$pb.TagNumber(10)
  set height($core.int v) { $_setSignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasHeight() => $_has(9);
  @$pb.TagNumber(10)
  void clearHeight() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get duration => $_getIZ(10);
  @$pb.TagNumber(11)
  set duration($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasDuration() => $_has(10);
  @$pb.TagNumber(11)
  void clearDuration() => clearField(11);
}

class EngineGetSharedMediaResponse extends $pb.GeneratedMessage {
  factory EngineGetSharedMediaResponse({
    $core.Iterable<EngineSharedMediaItem>? items,
  }) {
    final $result = create();
    if (items != null) {
      $result.items.addAll(items);
    }
    return $result;
  }
  EngineGetSharedMediaResponse._() : super();
  factory EngineGetSharedMediaResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetSharedMediaResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSharedMediaResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineSharedMediaItem>(1, _omitFieldNames ? '' : 'items', $pb.PbFieldType.PM, subBuilder: EngineSharedMediaItem.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetSharedMediaResponse clone() => EngineGetSharedMediaResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetSharedMediaResponse copyWith(void Function(EngineGetSharedMediaResponse) updates) => super.copyWith((message) => updates(message as EngineGetSharedMediaResponse)) as EngineGetSharedMediaResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSharedMediaResponse create() => EngineGetSharedMediaResponse._();
  EngineGetSharedMediaResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetSharedMediaResponse> createRepeated() => $pb.PbList<EngineGetSharedMediaResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSharedMediaResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSharedMediaResponse>(create);
  static EngineGetSharedMediaResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineSharedMediaItem> get items => $_getList(0);
}

class EngineGetSharedMediaCountsRequest extends $pb.GeneratedMessage {
  factory EngineGetSharedMediaCountsRequest({
    $core.String? accountId,
    $core.String? chatId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  EngineGetSharedMediaCountsRequest._() : super();
  factory EngineGetSharedMediaCountsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetSharedMediaCountsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSharedMediaCountsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use [GeneratedMessageGenericExtensions.deepCopy] instead.')
  EngineGetSharedMediaCountsRequest clone() => EngineGetSharedMediaCountsRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use [GeneratedMessageGenericExtensions.rebuild] instead.')
  EngineGetSharedMediaCountsRequest copyWith(void Function(EngineGetSharedMediaCountsRequest) updates) => super.copyWith((message) => updates(message as EngineGetSharedMediaCountsRequest)) as EngineGetSharedMediaCountsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSharedMediaCountsRequest create() => EngineGetSharedMediaCountsRequest._();
  EngineGetSharedMediaCountsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetSharedMediaCountsRequest> createRepeated() => $pb.PbList<EngineGetSharedMediaCountsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSharedMediaCountsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSharedMediaCountsRequest>(create);
  static EngineGetSharedMediaCountsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class EngineSharedMediaCount extends $pb.GeneratedMessage {
  factory EngineSharedMediaCount({
    $core.String? mediaType,
    $core.int? count,
  }) {
    final $result = create();
    if (mediaType != null) {
      $result.mediaType = mediaType;
    }
    if (count != null) {
      $result.count = count;
    }
    return $result;
  }
  EngineSharedMediaCount._() : super();
  factory EngineSharedMediaCount.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSharedMediaCount.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSharedMediaCount', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'mediaType')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'count', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use [GeneratedMessageGenericExtensions.deepCopy] instead.')
  EngineSharedMediaCount clone() => EngineSharedMediaCount()..mergeFromMessage(this);
  @$core.Deprecated('Use [GeneratedMessageGenericExtensions.rebuild] instead.')
  EngineSharedMediaCount copyWith(void Function(EngineSharedMediaCount) updates) => super.copyWith((message) => updates(message as EngineSharedMediaCount)) as EngineSharedMediaCount;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSharedMediaCount create() => EngineSharedMediaCount._();
  EngineSharedMediaCount createEmptyInstance() => create();
  static $pb.PbList<EngineSharedMediaCount> createRepeated() => $pb.PbList<EngineSharedMediaCount>();
  @$core.pragma('dart2js:noInline')
  static EngineSharedMediaCount getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSharedMediaCount>(create);
  static EngineSharedMediaCount? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get mediaType => $_getSZ(0);
  @$pb.TagNumber(1)
  set mediaType($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMediaType() => $_has(0);
  @$pb.TagNumber(1)
  void clearMediaType() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get count => $_getIZ(1);
  @$pb.TagNumber(2)
  set count($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearCount() => clearField(2);
}

class EngineGetSharedMediaCountsResponse extends $pb.GeneratedMessage {
  factory EngineGetSharedMediaCountsResponse({
    $core.Iterable<EngineSharedMediaCount>? counts,
  }) {
    final $result = create();
    if (counts != null) {
      $result.counts.addAll(counts);
    }
    return $result;
  }
  EngineGetSharedMediaCountsResponse._() : super();
  factory EngineGetSharedMediaCountsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetSharedMediaCountsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSharedMediaCountsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineSharedMediaCount>(1, _omitFieldNames ? '' : 'counts', $pb.PbFieldType.PM, subBuilder: EngineSharedMediaCount.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use [GeneratedMessageGenericExtensions.deepCopy] instead.')
  EngineGetSharedMediaCountsResponse clone() => EngineGetSharedMediaCountsResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use [GeneratedMessageGenericExtensions.rebuild] instead.')
  EngineGetSharedMediaCountsResponse copyWith(void Function(EngineGetSharedMediaCountsResponse) updates) => super.copyWith((message) => updates(message as EngineGetSharedMediaCountsResponse)) as EngineGetSharedMediaCountsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSharedMediaCountsResponse create() => EngineGetSharedMediaCountsResponse._();
  EngineGetSharedMediaCountsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetSharedMediaCountsResponse> createRepeated() => $pb.PbList<EngineGetSharedMediaCountsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSharedMediaCountsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSharedMediaCountsResponse>(create);
  static EngineGetSharedMediaCountsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineSharedMediaCount> get counts => $_getList(0);
}

class EngineGetConfigResponse extends $pb.GeneratedMessage {
  factory EngineGetConfigResponse({
    $core.String? theme,
    $core.String? accentColor,
    $core.double? fontScale,
    $core.String? language,
    $core.String? downloadDir,
    $fixnum.Int64? maxCacheSize,
    $core.bool? sendReadReceipts,
    $core.bool? sendTyping,
    $core.bool? notifyDms,
    $core.bool? notifyGroups,
    $core.bool? notifyMentionsOnly,
  }) {
    final $result = create();
    if (theme != null) {
      $result.theme = theme;
    }
    if (accentColor != null) {
      $result.accentColor = accentColor;
    }
    if (fontScale != null) {
      $result.fontScale = fontScale;
    }
    if (language != null) {
      $result.language = language;
    }
    if (downloadDir != null) {
      $result.downloadDir = downloadDir;
    }
    if (maxCacheSize != null) {
      $result.maxCacheSize = maxCacheSize;
    }
    if (sendReadReceipts != null) {
      $result.sendReadReceipts = sendReadReceipts;
    }
    if (sendTyping != null) {
      $result.sendTyping = sendTyping;
    }
    if (notifyDms != null) {
      $result.notifyDms = notifyDms;
    }
    if (notifyGroups != null) {
      $result.notifyGroups = notifyGroups;
    }
    if (notifyMentionsOnly != null) {
      $result.notifyMentionsOnly = notifyMentionsOnly;
    }
    return $result;
  }
  EngineGetConfigResponse._() : super();
  factory EngineGetConfigResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetConfigResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetConfigResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'theme')
    ..aOS(2, _omitFieldNames ? '' : 'accentColor')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'fontScale', $pb.PbFieldType.OD)
    ..aOS(4, _omitFieldNames ? '' : 'language')
    ..aOS(5, _omitFieldNames ? '' : 'downloadDir')
    ..aInt64(6, _omitFieldNames ? '' : 'maxCacheSize')
    ..aOB(7, _omitFieldNames ? '' : 'sendReadReceipts')
    ..aOB(8, _omitFieldNames ? '' : 'sendTyping')
    ..aOB(9, _omitFieldNames ? '' : 'notifyDms')
    ..aOB(10, _omitFieldNames ? '' : 'notifyGroups')
    ..aOB(11, _omitFieldNames ? '' : 'notifyMentionsOnly')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetConfigResponse clone() => EngineGetConfigResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetConfigResponse copyWith(void Function(EngineGetConfigResponse) updates) => super.copyWith((message) => updates(message as EngineGetConfigResponse)) as EngineGetConfigResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetConfigResponse create() => EngineGetConfigResponse._();
  EngineGetConfigResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetConfigResponse> createRepeated() => $pb.PbList<EngineGetConfigResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetConfigResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetConfigResponse>(create);
  static EngineGetConfigResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get theme => $_getSZ(0);
  @$pb.TagNumber(1)
  set theme($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTheme() => $_has(0);
  @$pb.TagNumber(1)
  void clearTheme() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get accentColor => $_getSZ(1);
  @$pb.TagNumber(2)
  set accentColor($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccentColor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccentColor() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get fontScale => $_getN(2);
  @$pb.TagNumber(3)
  set fontScale($core.double v) { $_setDouble(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFontScale() => $_has(2);
  @$pb.TagNumber(3)
  void clearFontScale() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get language => $_getSZ(3);
  @$pb.TagNumber(4)
  set language($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLanguage() => $_has(3);
  @$pb.TagNumber(4)
  void clearLanguage() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get downloadDir => $_getSZ(4);
  @$pb.TagNumber(5)
  set downloadDir($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasDownloadDir() => $_has(4);
  @$pb.TagNumber(5)
  void clearDownloadDir() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get maxCacheSize => $_getI64(5);
  @$pb.TagNumber(6)
  set maxCacheSize($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasMaxCacheSize() => $_has(5);
  @$pb.TagNumber(6)
  void clearMaxCacheSize() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get sendReadReceipts => $_getBF(6);
  @$pb.TagNumber(7)
  set sendReadReceipts($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasSendReadReceipts() => $_has(6);
  @$pb.TagNumber(7)
  void clearSendReadReceipts() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get sendTyping => $_getBF(7);
  @$pb.TagNumber(8)
  set sendTyping($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSendTyping() => $_has(7);
  @$pb.TagNumber(8)
  void clearSendTyping() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get notifyDms => $_getBF(8);
  @$pb.TagNumber(9)
  set notifyDms($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasNotifyDms() => $_has(8);
  @$pb.TagNumber(9)
  void clearNotifyDms() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get notifyGroups => $_getBF(9);
  @$pb.TagNumber(10)
  set notifyGroups($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasNotifyGroups() => $_has(9);
  @$pb.TagNumber(10)
  void clearNotifyGroups() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get notifyMentionsOnly => $_getBF(10);
  @$pb.TagNumber(11)
  set notifyMentionsOnly($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasNotifyMentionsOnly() => $_has(10);
  @$pb.TagNumber(11)
  void clearNotifyMentionsOnly() => clearField(11);
}

class EngineUpdateConfigRequest extends $pb.GeneratedMessage {
  factory EngineUpdateConfigRequest({
    $core.String? theme,
    $core.String? accentColor,
    $core.double? fontScale,
    $core.String? language,
    $fixnum.Int64? maxCacheSize,
    $core.bool? sendReadReceipts,
    $core.bool? hasSendReadReceipts_7,
    $core.bool? sendTyping,
    $core.bool? hasSendTyping_9,
    $core.bool? notifyDms,
    $core.bool? hasNotifyDms_11,
    $core.bool? notifyGroups,
    $core.bool? hasNotifyGroups_13,
    $core.bool? notifyMentionsOnly,
    $core.bool? hasNotifyMentionsOnly_15,
  }) {
    final $result = create();
    if (theme != null) {
      $result.theme = theme;
    }
    if (accentColor != null) {
      $result.accentColor = accentColor;
    }
    if (fontScale != null) {
      $result.fontScale = fontScale;
    }
    if (language != null) {
      $result.language = language;
    }
    if (maxCacheSize != null) {
      $result.maxCacheSize = maxCacheSize;
    }
    if (sendReadReceipts != null) {
      $result.sendReadReceipts = sendReadReceipts;
    }
    if (hasSendReadReceipts_7 != null) {
      $result.hasSendReadReceipts_7 = hasSendReadReceipts_7;
    }
    if (sendTyping != null) {
      $result.sendTyping = sendTyping;
    }
    if (hasSendTyping_9 != null) {
      $result.hasSendTyping_9 = hasSendTyping_9;
    }
    if (notifyDms != null) {
      $result.notifyDms = notifyDms;
    }
    if (hasNotifyDms_11 != null) {
      $result.hasNotifyDms_11 = hasNotifyDms_11;
    }
    if (notifyGroups != null) {
      $result.notifyGroups = notifyGroups;
    }
    if (hasNotifyGroups_13 != null) {
      $result.hasNotifyGroups_13 = hasNotifyGroups_13;
    }
    if (notifyMentionsOnly != null) {
      $result.notifyMentionsOnly = notifyMentionsOnly;
    }
    if (hasNotifyMentionsOnly_15 != null) {
      $result.hasNotifyMentionsOnly_15 = hasNotifyMentionsOnly_15;
    }
    return $result;
  }
  EngineUpdateConfigRequest._() : super();
  factory EngineUpdateConfigRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineUpdateConfigRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineUpdateConfigRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'theme')
    ..aOS(2, _omitFieldNames ? '' : 'accentColor')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'fontScale', $pb.PbFieldType.OD)
    ..aOS(4, _omitFieldNames ? '' : 'language')
    ..aInt64(5, _omitFieldNames ? '' : 'maxCacheSize')
    ..aOB(6, _omitFieldNames ? '' : 'sendReadReceipts')
    ..aOB(7, _omitFieldNames ? '' : 'hasSendReadReceipts')
    ..aOB(8, _omitFieldNames ? '' : 'sendTyping')
    ..aOB(9, _omitFieldNames ? '' : 'hasSendTyping')
    ..aOB(10, _omitFieldNames ? '' : 'notifyDms')
    ..aOB(11, _omitFieldNames ? '' : 'hasNotifyDms')
    ..aOB(12, _omitFieldNames ? '' : 'notifyGroups')
    ..aOB(13, _omitFieldNames ? '' : 'hasNotifyGroups')
    ..aOB(14, _omitFieldNames ? '' : 'notifyMentionsOnly')
    ..aOB(15, _omitFieldNames ? '' : 'hasNotifyMentionsOnly')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineUpdateConfigRequest clone() => EngineUpdateConfigRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineUpdateConfigRequest copyWith(void Function(EngineUpdateConfigRequest) updates) => super.copyWith((message) => updates(message as EngineUpdateConfigRequest)) as EngineUpdateConfigRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineUpdateConfigRequest create() => EngineUpdateConfigRequest._();
  EngineUpdateConfigRequest createEmptyInstance() => create();
  static $pb.PbList<EngineUpdateConfigRequest> createRepeated() => $pb.PbList<EngineUpdateConfigRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineUpdateConfigRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineUpdateConfigRequest>(create);
  static EngineUpdateConfigRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get theme => $_getSZ(0);
  @$pb.TagNumber(1)
  set theme($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTheme() => $_has(0);
  @$pb.TagNumber(1)
  void clearTheme() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get accentColor => $_getSZ(1);
  @$pb.TagNumber(2)
  set accentColor($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasAccentColor() => $_has(1);
  @$pb.TagNumber(2)
  void clearAccentColor() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get fontScale => $_getN(2);
  @$pb.TagNumber(3)
  set fontScale($core.double v) { $_setDouble(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasFontScale() => $_has(2);
  @$pb.TagNumber(3)
  void clearFontScale() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get language => $_getSZ(3);
  @$pb.TagNumber(4)
  set language($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLanguage() => $_has(3);
  @$pb.TagNumber(4)
  void clearLanguage() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get maxCacheSize => $_getI64(4);
  @$pb.TagNumber(5)
  set maxCacheSize($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMaxCacheSize() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxCacheSize() => clearField(5);

  /// Privacy — use has_* flags since false is a valid value (not "unset").
  @$pb.TagNumber(6)
  $core.bool get sendReadReceipts => $_getBF(5);
  @$pb.TagNumber(6)
  set sendReadReceipts($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSendReadReceipts() => $_has(5);
  @$pb.TagNumber(6)
  void clearSendReadReceipts() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get hasSendReadReceipts_7 => $_getBF(6);
  @$pb.TagNumber(7)
  set hasSendReadReceipts_7($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasHasSendReadReceipts_7() => $_has(6);
  @$pb.TagNumber(7)
  void clearHasSendReadReceipts_7() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get sendTyping => $_getBF(7);
  @$pb.TagNumber(8)
  set sendTyping($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasSendTyping() => $_has(7);
  @$pb.TagNumber(8)
  void clearSendTyping() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get hasSendTyping_9 => $_getBF(8);
  @$pb.TagNumber(9)
  set hasSendTyping_9($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasHasSendTyping_9() => $_has(8);
  @$pb.TagNumber(9)
  void clearHasSendTyping_9() => clearField(9);

  /// Notifications
  @$pb.TagNumber(10)
  $core.bool get notifyDms => $_getBF(9);
  @$pb.TagNumber(10)
  set notifyDms($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasNotifyDms() => $_has(9);
  @$pb.TagNumber(10)
  void clearNotifyDms() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get hasNotifyDms_11 => $_getBF(10);
  @$pb.TagNumber(11)
  set hasNotifyDms_11($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasHasNotifyDms_11() => $_has(10);
  @$pb.TagNumber(11)
  void clearHasNotifyDms_11() => clearField(11);

  @$pb.TagNumber(12)
  $core.bool get notifyGroups => $_getBF(11);
  @$pb.TagNumber(12)
  set notifyGroups($core.bool v) { $_setBool(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasNotifyGroups() => $_has(11);
  @$pb.TagNumber(12)
  void clearNotifyGroups() => clearField(12);

  @$pb.TagNumber(13)
  $core.bool get hasNotifyGroups_13 => $_getBF(12);
  @$pb.TagNumber(13)
  set hasNotifyGroups_13($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasHasNotifyGroups_13() => $_has(12);
  @$pb.TagNumber(13)
  void clearHasNotifyGroups_13() => clearField(13);

  @$pb.TagNumber(14)
  $core.bool get notifyMentionsOnly => $_getBF(13);
  @$pb.TagNumber(14)
  set notifyMentionsOnly($core.bool v) { $_setBool(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasNotifyMentionsOnly() => $_has(13);
  @$pb.TagNumber(14)
  void clearNotifyMentionsOnly() => clearField(14);

  @$pb.TagNumber(15)
  $core.bool get hasNotifyMentionsOnly_15 => $_getBF(14);
  @$pb.TagNumber(15)
  set hasNotifyMentionsOnly_15($core.bool v) { $_setBool(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasHasNotifyMentionsOnly_15() => $_has(14);
  @$pb.TagNumber(15)
  void clearHasNotifyMentionsOnly_15() => clearField(15);
}

class EngineFolderInfo extends $pb.GeneratedMessage {
  factory EngineFolderInfo({
    $core.String? id,
    $core.String? name,
    $core.Iterable<$core.String>? chatIds,
    $core.Iterable<$core.String>? excludeChatIds,
    $core.Iterable<$core.String>? pinnedChatIds,
    $core.bool? contacts,
    $core.bool? nonContacts,
    $core.bool? groups,
    $core.bool? channels,
    $core.bool? bots,
    $core.bool? excludeMuted,
    $core.bool? excludeRead,
    $core.bool? excludeArchived,
    $core.bool? isChatList,
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
    if (excludeChatIds != null) {
      $result.excludeChatIds.addAll(excludeChatIds);
    }
    if (pinnedChatIds != null) {
      $result.pinnedChatIds.addAll(pinnedChatIds);
    }
    if (contacts != null) {
      $result.contacts = contacts;
    }
    if (nonContacts != null) {
      $result.nonContacts = nonContacts;
    }
    if (groups != null) {
      $result.groups = groups;
    }
    if (channels != null) {
      $result.channels = channels;
    }
    if (bots != null) {
      $result.bots = bots;
    }
    if (excludeMuted != null) {
      $result.excludeMuted = excludeMuted;
    }
    if (excludeRead != null) {
      $result.excludeRead = excludeRead;
    }
    if (excludeArchived != null) {
      $result.excludeArchived = excludeArchived;
    }
    if (isChatList != null) {
      $result.isChatList = isChatList;
    }
    return $result;
  }
  EngineFolderInfo._() : super();
  factory EngineFolderInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineFolderInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineFolderInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..pPS(3, _omitFieldNames ? '' : 'chatIds')
    ..pPS(4, _omitFieldNames ? '' : 'excludeChatIds')
    ..pPS(5, _omitFieldNames ? '' : 'pinnedChatIds')
    ..aOB(6, _omitFieldNames ? '' : 'contacts')
    ..aOB(7, _omitFieldNames ? '' : 'nonContacts')
    ..aOB(8, _omitFieldNames ? '' : 'groups')
    ..aOB(9, _omitFieldNames ? '' : 'channels')
    ..aOB(10, _omitFieldNames ? '' : 'bots')
    ..aOB(11, _omitFieldNames ? '' : 'excludeMuted')
    ..aOB(12, _omitFieldNames ? '' : 'excludeRead')
    ..aOB(13, _omitFieldNames ? '' : 'excludeArchived')
    ..aOB(14, _omitFieldNames ? '' : 'isChatList')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineFolderInfo clone() => EngineFolderInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineFolderInfo copyWith(void Function(EngineFolderInfo) updates) => super.copyWith((message) => updates(message as EngineFolderInfo)) as EngineFolderInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineFolderInfo create() => EngineFolderInfo._();
  EngineFolderInfo createEmptyInstance() => create();
  static $pb.PbList<EngineFolderInfo> createRepeated() => $pb.PbList<EngineFolderInfo>();
  @$core.pragma('dart2js:noInline')
  static EngineFolderInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineFolderInfo>(create);
  static EngineFolderInfo? _defaultInstance;

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

  @$pb.TagNumber(4)
  $core.List<$core.String> get excludeChatIds => $_getList(3);

  @$pb.TagNumber(5)
  $core.List<$core.String> get pinnedChatIds => $_getList(4);

  @$pb.TagNumber(6)
  $core.bool get contacts => $_getBF(5);
  @$pb.TagNumber(6)
  set contacts($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasContacts() => $_has(5);
  @$pb.TagNumber(6)
  void clearContacts() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get nonContacts => $_getBF(6);
  @$pb.TagNumber(7)
  set nonContacts($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasNonContacts() => $_has(6);
  @$pb.TagNumber(7)
  void clearNonContacts() => clearField(7);

  @$pb.TagNumber(8)
  $core.bool get groups => $_getBF(7);
  @$pb.TagNumber(8)
  set groups($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasGroups() => $_has(7);
  @$pb.TagNumber(8)
  void clearGroups() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get channels => $_getBF(8);
  @$pb.TagNumber(9)
  set channels($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasChannels() => $_has(8);
  @$pb.TagNumber(9)
  void clearChannels() => clearField(9);

  @$pb.TagNumber(10)
  $core.bool get bots => $_getBF(9);
  @$pb.TagNumber(10)
  set bots($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasBots() => $_has(9);
  @$pb.TagNumber(10)
  void clearBots() => clearField(10);

  @$pb.TagNumber(11)
  $core.bool get excludeMuted => $_getBF(10);
  @$pb.TagNumber(11)
  set excludeMuted($core.bool v) { $_setBool(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasExcludeMuted() => $_has(10);
  @$pb.TagNumber(11)
  void clearExcludeMuted() => clearField(11);

  @$pb.TagNumber(12)
  $core.bool get excludeRead => $_getBF(11);
  @$pb.TagNumber(12)
  set excludeRead($core.bool v) { $_setBool(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasExcludeRead() => $_has(11);
  @$pb.TagNumber(12)
  void clearExcludeRead() => clearField(12);

  @$pb.TagNumber(13)
  $core.bool get excludeArchived => $_getBF(12);
  @$pb.TagNumber(13)
  set excludeArchived($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasExcludeArchived() => $_has(12);
  @$pb.TagNumber(13)
  void clearExcludeArchived() => clearField(13);

  @$pb.TagNumber(14)
  $core.bool get isChatList => $_getBF(13);
  @$pb.TagNumber(14)
  set isChatList($core.bool v) { $_setBool(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasIsChatList() => $_has(13);
  @$pb.TagNumber(14)
  void clearIsChatList() => clearField(14);
}

class EngineGetFoldersRequest extends $pb.GeneratedMessage {
  factory EngineGetFoldersRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineGetFoldersRequest._() : super();
  factory EngineGetFoldersRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetFoldersRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetFoldersRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetFoldersRequest clone() => EngineGetFoldersRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetFoldersRequest copyWith(void Function(EngineGetFoldersRequest) updates) => super.copyWith((message) => updates(message as EngineGetFoldersRequest)) as EngineGetFoldersRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetFoldersRequest create() => EngineGetFoldersRequest._();
  EngineGetFoldersRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetFoldersRequest> createRepeated() => $pb.PbList<EngineGetFoldersRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetFoldersRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetFoldersRequest>(create);
  static EngineGetFoldersRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class EngineGetFoldersResponse extends $pb.GeneratedMessage {
  factory EngineGetFoldersResponse({
    $core.Iterable<EngineFolderInfo>? folders,
  }) {
    final $result = create();
    if (folders != null) {
      $result.folders.addAll(folders);
    }
    return $result;
  }
  EngineGetFoldersResponse._() : super();
  factory EngineGetFoldersResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetFoldersResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetFoldersResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineFolderInfo>(1, _omitFieldNames ? '' : 'folders', $pb.PbFieldType.PM, subBuilder: EngineFolderInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetFoldersResponse clone() => EngineGetFoldersResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetFoldersResponse copyWith(void Function(EngineGetFoldersResponse) updates) => super.copyWith((message) => updates(message as EngineGetFoldersResponse)) as EngineGetFoldersResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetFoldersResponse create() => EngineGetFoldersResponse._();
  EngineGetFoldersResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetFoldersResponse> createRepeated() => $pb.PbList<EngineGetFoldersResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetFoldersResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetFoldersResponse>(create);
  static EngineGetFoldersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineFolderInfo> get folders => $_getList(0);
}

class EngineDeleteFolderRequest extends $pb.GeneratedMessage {
  factory EngineDeleteFolderRequest({
    $core.String? accountId,
    $core.String? folderId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (folderId != null) {
      $result.folderId = folderId;
    }
    return $result;
  }
  EngineDeleteFolderRequest._() : super();
  factory EngineDeleteFolderRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineDeleteFolderRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineDeleteFolderRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'folderId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineDeleteFolderRequest clone() => EngineDeleteFolderRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineDeleteFolderRequest copyWith(void Function(EngineDeleteFolderRequest) updates) => super.copyWith((message) => updates(message as EngineDeleteFolderRequest)) as EngineDeleteFolderRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineDeleteFolderRequest create() => EngineDeleteFolderRequest._();
  EngineDeleteFolderRequest createEmptyInstance() => create();
  static $pb.PbList<EngineDeleteFolderRequest> createRepeated() => $pb.PbList<EngineDeleteFolderRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineDeleteFolderRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineDeleteFolderRequest>(create);
  static EngineDeleteFolderRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get folderId => $_getSZ(1);
  @$pb.TagNumber(2)
  set folderId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFolderId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFolderId() => clearField(2);
}

class EngineEditFolderRequest extends $pb.GeneratedMessage {
  factory EngineEditFolderRequest({
    $core.String? accountId,
    $core.String? folderId,
    $core.String? title,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (folderId != null) {
      $result.folderId = folderId;
    }
    if (title != null) {
      $result.title = title;
    }
    return $result;
  }
  EngineEditFolderRequest._() : super();
  factory EngineEditFolderRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineEditFolderRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineEditFolderRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'folderId')
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineEditFolderRequest clone() => EngineEditFolderRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineEditFolderRequest copyWith(void Function(EngineEditFolderRequest) updates) => super.copyWith((message) => updates(message as EngineEditFolderRequest)) as EngineEditFolderRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineEditFolderRequest create() => EngineEditFolderRequest._();
  EngineEditFolderRequest createEmptyInstance() => create();
  static $pb.PbList<EngineEditFolderRequest> createRepeated() => $pb.PbList<EngineEditFolderRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineEditFolderRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineEditFolderRequest>(create);
  static EngineEditFolderRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get folderId => $_getSZ(1);
  @$pb.TagNumber(2)
  set folderId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasFolderId() => $_has(1);
  @$pb.TagNumber(2)
  void clearFolderId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTitle() => $_has(2);
  @$pb.TagNumber(3)
  void clearTitle() => clearField(3);
}

class EngineGetPinnedMessagesRequest extends $pb.GeneratedMessage {
  factory EngineGetPinnedMessagesRequest({
    $core.String? accountId,
    $core.String? chatId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  EngineGetPinnedMessagesRequest._() : super();
  factory EngineGetPinnedMessagesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetPinnedMessagesRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetPinnedMessagesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetPinnedMessagesRequest clone() => EngineGetPinnedMessagesRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetPinnedMessagesRequest copyWith(void Function(EngineGetPinnedMessagesRequest) updates) => super.copyWith((message) => updates(message as EngineGetPinnedMessagesRequest)) as EngineGetPinnedMessagesRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetPinnedMessagesRequest create() => EngineGetPinnedMessagesRequest._();
  EngineGetPinnedMessagesRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetPinnedMessagesRequest> createRepeated() => $pb.PbList<EngineGetPinnedMessagesRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetPinnedMessagesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetPinnedMessagesRequest>(create);
  static EngineGetPinnedMessagesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class EngineGetPinnedMessagesResponse extends $pb.GeneratedMessage {
  factory EngineGetPinnedMessagesResponse({
    $core.Iterable<EngineCachedMessage>? messages,
  }) {
    final $result = create();
    if (messages != null) {
      $result.messages.addAll(messages);
    }
    return $result;
  }
  EngineGetPinnedMessagesResponse._() : super();
  factory EngineGetPinnedMessagesResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetPinnedMessagesResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetPinnedMessagesResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineCachedMessage>(1, _omitFieldNames ? '' : 'messages', $pb.PbFieldType.PM, subBuilder: EngineCachedMessage.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetPinnedMessagesResponse clone() => EngineGetPinnedMessagesResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetPinnedMessagesResponse copyWith(void Function(EngineGetPinnedMessagesResponse) updates) => super.copyWith((message) => updates(message as EngineGetPinnedMessagesResponse)) as EngineGetPinnedMessagesResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetPinnedMessagesResponse create() => EngineGetPinnedMessagesResponse._();
  EngineGetPinnedMessagesResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetPinnedMessagesResponse> createRepeated() => $pb.PbList<EngineGetPinnedMessagesResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetPinnedMessagesResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetPinnedMessagesResponse>(create);
  static EngineGetPinnedMessagesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineCachedMessage> get messages => $_getList(0);
}

class EngineCreateChannelRequest extends $pb.GeneratedMessage {
  factory EngineCreateChannelRequest({
    $core.String? accountId,
    $core.String? name,
    $core.String? description,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    return $result;
  }
  EngineCreateChannelRequest._() : super();
  factory EngineCreateChannelRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineCreateChannelRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCreateChannelRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..aOS(3, _omitFieldNames ? '' : 'description')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineCreateChannelRequest clone() => EngineCreateChannelRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineCreateChannelRequest copyWith(void Function(EngineCreateChannelRequest) updates) => super.copyWith((message) => updates(message as EngineCreateChannelRequest)) as EngineCreateChannelRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineCreateChannelRequest create() => EngineCreateChannelRequest._();
  EngineCreateChannelRequest createEmptyInstance() => create();
  static $pb.PbList<EngineCreateChannelRequest> createRepeated() => $pb.PbList<EngineCreateChannelRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineCreateChannelRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCreateChannelRequest>(create);
  static EngineCreateChannelRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get description => $_getSZ(2);
  @$pb.TagNumber(3)
  set description($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasDescription() => $_has(2);
  @$pb.TagNumber(3)
  void clearDescription() => clearField(3);
}

class EngineCreateChannelResponse extends $pb.GeneratedMessage {
  factory EngineCreateChannelResponse({
    EngineChatInfo? chat,
  }) {
    final $result = create();
    if (chat != null) {
      $result.chat = chat;
    }
    return $result;
  }
  EngineCreateChannelResponse._() : super();
  factory EngineCreateChannelResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineCreateChannelResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCreateChannelResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOM<EngineChatInfo>(1, _omitFieldNames ? '' : 'chat', subBuilder: EngineChatInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineCreateChannelResponse clone() => EngineCreateChannelResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineCreateChannelResponse copyWith(void Function(EngineCreateChannelResponse) updates) => super.copyWith((message) => updates(message as EngineCreateChannelResponse)) as EngineCreateChannelResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineCreateChannelResponse create() => EngineCreateChannelResponse._();
  EngineCreateChannelResponse createEmptyInstance() => create();
  static $pb.PbList<EngineCreateChannelResponse> createRepeated() => $pb.PbList<EngineCreateChannelResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineCreateChannelResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCreateChannelResponse>(create);
  static EngineCreateChannelResponse? _defaultInstance;

  @$pb.TagNumber(1)
  EngineChatInfo get chat => $_getN(0);
  @$pb.TagNumber(1)
  set chat(EngineChatInfo v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasChat() => $_has(0);
  @$pb.TagNumber(1)
  void clearChat() => clearField(1);
  @$pb.TagNumber(1)
  EngineChatInfo ensureChat() => $_ensure(0);
}

class EngineContactInfo extends $pb.GeneratedMessage {
  factory EngineContactInfo({
    $core.String? userId,
    $core.String? username,
    $core.String? displayName,
    $core.String? phone,
    $core.String? avatarB64,
    $core.bool? isBot,
    $core.bool? isOnline,
  }) {
    final $result = create();
    if (userId != null) {
      $result.userId = userId;
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
    if (avatarB64 != null) {
      $result.avatarB64 = avatarB64;
    }
    if (isBot != null) {
      $result.isBot = isBot;
    }
    if (isOnline != null) {
      $result.isOnline = isOnline;
    }
    return $result;
  }
  EngineContactInfo._() : super();
  factory EngineContactInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineContactInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineContactInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'username')
    ..aOS(3, _omitFieldNames ? '' : 'displayName')
    ..aOS(4, _omitFieldNames ? '' : 'phone')
    ..aOS(5, _omitFieldNames ? '' : 'avatarB64')
    ..aOB(6, _omitFieldNames ? '' : 'isBot')
    ..aOB(7, _omitFieldNames ? '' : 'isOnline')
    ..a<$core.int>(8, _omitFieldNames ? '' : 'storyCount', $pb.PbFieldType.O3)
    ..aOB(9, _omitFieldNames ? '' : 'hasUnreadStory')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineContactInfo clone() => EngineContactInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineContactInfo copyWith(void Function(EngineContactInfo) updates) => super.copyWith((message) => updates(message as EngineContactInfo)) as EngineContactInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineContactInfo create() => EngineContactInfo._();
  EngineContactInfo createEmptyInstance() => create();
  static $pb.PbList<EngineContactInfo> createRepeated() => $pb.PbList<EngineContactInfo>();
  @$core.pragma('dart2js:noInline')
  static EngineContactInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineContactInfo>(create);
  static EngineContactInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get userId => $_getSZ(0);
  @$pb.TagNumber(1)
  set userId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUserId() => $_has(0);
  @$pb.TagNumber(1)
  void clearUserId() => clearField(1);

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
  $core.String get avatarB64 => $_getSZ(4);
  @$pb.TagNumber(5)
  set avatarB64($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAvatarB64() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvatarB64() => clearField(5);

  @$pb.TagNumber(6)
  $core.bool get isBot => $_getBF(5);
  @$pb.TagNumber(6)
  set isBot($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasIsBot() => $_has(5);
  @$pb.TagNumber(6)
  void clearIsBot() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isOnline => $_getBF(6);
  @$pb.TagNumber(7)
  set isOnline($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasIsOnline() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsOnline() => clearField(7);

  @$pb.TagNumber(8)
  $core.int get storyCount => $_getIZ(7);
  @$pb.TagNumber(8)
  set storyCount($core.int v) { $_setSignedInt32(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasStoryCount() => $_has(7);
  @$pb.TagNumber(8)
  void clearStoryCount() => clearField(8);

  @$pb.TagNumber(9)
  $core.bool get hasUnreadStory => $_getBF(8);
  @$pb.TagNumber(9)
  set hasUnreadStory($core.bool v) { $_setBool(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasHasUnreadStory() => $_has(8);
  @$pb.TagNumber(9)
  void clearHasUnreadStory() => clearField(9);
}

class EngineGetContactsRequest extends $pb.GeneratedMessage {
  factory EngineGetContactsRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineGetContactsRequest._() : super();
  factory EngineGetContactsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetContactsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetContactsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetContactsRequest clone() => EngineGetContactsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetContactsRequest copyWith(void Function(EngineGetContactsRequest) updates) => super.copyWith((message) => updates(message as EngineGetContactsRequest)) as EngineGetContactsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetContactsRequest create() => EngineGetContactsRequest._();
  EngineGetContactsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetContactsRequest> createRepeated() => $pb.PbList<EngineGetContactsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetContactsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetContactsRequest>(create);
  static EngineGetContactsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class EngineGetContactsResponse extends $pb.GeneratedMessage {
  factory EngineGetContactsResponse({
    $core.Iterable<EngineContactInfo>? contacts,
  }) {
    final $result = create();
    if (contacts != null) {
      $result.contacts.addAll(contacts);
    }
    return $result;
  }
  EngineGetContactsResponse._() : super();
  factory EngineGetContactsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetContactsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetContactsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineContactInfo>(1, _omitFieldNames ? '' : 'contacts', $pb.PbFieldType.PM, subBuilder: EngineContactInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetContactsResponse clone() => EngineGetContactsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetContactsResponse copyWith(void Function(EngineGetContactsResponse) updates) => super.copyWith((message) => updates(message as EngineGetContactsResponse)) as EngineGetContactsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetContactsResponse create() => EngineGetContactsResponse._();
  EngineGetContactsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetContactsResponse> createRepeated() => $pb.PbList<EngineGetContactsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetContactsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetContactsResponse>(create);
  static EngineGetContactsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineContactInfo> get contacts => $_getList(0);
}

class EngineGetOnlineCountRequest extends $pb.GeneratedMessage {
  factory EngineGetOnlineCountRequest({
    $core.String? accountId,
    $core.String? chatId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  EngineGetOnlineCountRequest._() : super();
  factory EngineGetOnlineCountRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetOnlineCountRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetOnlineCountRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetOnlineCountRequest clone() => EngineGetOnlineCountRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetOnlineCountRequest copyWith(void Function(EngineGetOnlineCountRequest) updates) => super.copyWith((message) => updates(message as EngineGetOnlineCountRequest)) as EngineGetOnlineCountRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetOnlineCountRequest create() => EngineGetOnlineCountRequest._();
  EngineGetOnlineCountRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetOnlineCountRequest> createRepeated() => $pb.PbList<EngineGetOnlineCountRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetOnlineCountRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetOnlineCountRequest>(create);
  static EngineGetOnlineCountRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class EngineGetOnlineCountResponse extends $pb.GeneratedMessage {
  factory EngineGetOnlineCountResponse({
    $core.int? onlineCount,
  }) {
    final $result = create();
    if (onlineCount != null) {
      $result.onlineCount = onlineCount;
    }
    return $result;
  }
  EngineGetOnlineCountResponse._() : super();
  factory EngineGetOnlineCountResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetOnlineCountResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetOnlineCountResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'onlineCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetOnlineCountResponse clone() => EngineGetOnlineCountResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetOnlineCountResponse copyWith(void Function(EngineGetOnlineCountResponse) updates) => super.copyWith((message) => updates(message as EngineGetOnlineCountResponse)) as EngineGetOnlineCountResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetOnlineCountResponse create() => EngineGetOnlineCountResponse._();
  EngineGetOnlineCountResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetOnlineCountResponse> createRepeated() => $pb.PbList<EngineGetOnlineCountResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetOnlineCountResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetOnlineCountResponse>(create);
  static EngineGetOnlineCountResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get onlineCount => $_getIZ(0);
  @$pb.TagNumber(1)
  set onlineCount($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOnlineCount() => $_has(0);
  @$pb.TagNumber(1)
  void clearOnlineCount() => clearField(1);
}

class EngineGroupCallParticipant extends $pb.GeneratedMessage {
  factory EngineGroupCallParticipant({
    $core.String? userId,
    $core.String? displayName,
    $core.bool? isMuted,
    $core.bool? isSpeaking,
    $core.bool? hasVideo,
    $core.String? avatarPath,
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
    if (avatarPath != null) {
      $result.avatarPath = avatarPath;
    }
    return $result;
  }
  EngineGroupCallParticipant._() : super();
  factory EngineGroupCallParticipant.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGroupCallParticipant.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGroupCallParticipant', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'userId')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOB(3, _omitFieldNames ? '' : 'isMuted')
    ..aOB(4, _omitFieldNames ? '' : 'isSpeaking')
    ..aOB(5, _omitFieldNames ? '' : 'hasVideo')
    ..aOS(6, _omitFieldNames ? '' : 'avatarPath')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGroupCallParticipant clone() => EngineGroupCallParticipant()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGroupCallParticipant copyWith(void Function(EngineGroupCallParticipant) updates) => super.copyWith((message) => updates(message as EngineGroupCallParticipant)) as EngineGroupCallParticipant;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGroupCallParticipant create() => EngineGroupCallParticipant._();
  EngineGroupCallParticipant createEmptyInstance() => create();
  static $pb.PbList<EngineGroupCallParticipant> createRepeated() => $pb.PbList<EngineGroupCallParticipant>();
  @$core.pragma('dart2js:noInline')
  static EngineGroupCallParticipant getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGroupCallParticipant>(create);
  static EngineGroupCallParticipant? _defaultInstance;

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

  @$pb.TagNumber(6)
  $core.String get avatarPath => $_getSZ(5);
  @$pb.TagNumber(6)
  set avatarPath($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasAvatarPath() => $_has(5);
  @$pb.TagNumber(6)
  void clearAvatarPath() => clearField(6);
}

class EngineGroupCallInfo extends $pb.GeneratedMessage {
  factory EngineGroupCallInfo({
    $core.String? callId,
    $core.String? chatId,
    $core.String? title,
    $core.int? participantsCount,
    $core.Iterable<EngineGroupCallParticipant>? participants,
    $core.bool? active,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (title != null) {
      $result.title = title;
    }
    if (participantsCount != null) {
      $result.participantsCount = participantsCount;
    }
    if (participants != null) {
      $result.participants.addAll(participants);
    }
    if (active != null) {
      $result.active = active;
    }
    return $result;
  }
  EngineGroupCallInfo._() : super();
  factory EngineGroupCallInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGroupCallInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGroupCallInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'callId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'participantsCount', $pb.PbFieldType.O3)
    ..pc<EngineGroupCallParticipant>(5, _omitFieldNames ? '' : 'participants', $pb.PbFieldType.PM, subBuilder: EngineGroupCallParticipant.create)
    ..aOB(6, _omitFieldNames ? '' : 'active')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGroupCallInfo clone() => EngineGroupCallInfo()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGroupCallInfo copyWith(void Function(EngineGroupCallInfo) updates) => super.copyWith((message) => updates(message as EngineGroupCallInfo)) as EngineGroupCallInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGroupCallInfo create() => EngineGroupCallInfo._();
  EngineGroupCallInfo createEmptyInstance() => create();
  static $pb.PbList<EngineGroupCallInfo> createRepeated() => $pb.PbList<EngineGroupCallInfo>();
  @$core.pragma('dart2js:noInline')
  static EngineGroupCallInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGroupCallInfo>(create);
  static EngineGroupCallInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get callId => $_getSZ(0);
  @$pb.TagNumber(1)
  set callId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTitle() => $_has(2);
  @$pb.TagNumber(3)
  void clearTitle() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get participantsCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set participantsCount($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasParticipantsCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearParticipantsCount() => clearField(4);

  @$pb.TagNumber(5)
  $core.List<EngineGroupCallParticipant> get participants => $_getList(4);

  @$pb.TagNumber(6)
  $core.bool get active => $_getBF(5);
  @$pb.TagNumber(6)
  set active($core.bool v) { $_setBool(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasActive() => $_has(5);
  @$pb.TagNumber(6)
  void clearActive() => clearField(6);
}

class EngineGetGroupCallRequest extends $pb.GeneratedMessage {
  factory EngineGetGroupCallRequest({
    $core.String? accountId,
    $core.String? chatId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  EngineGetGroupCallRequest._() : super();
  factory EngineGetGroupCallRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetGroupCallRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetGroupCallRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetGroupCallRequest clone() => EngineGetGroupCallRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetGroupCallRequest copyWith(void Function(EngineGetGroupCallRequest) updates) => super.copyWith((message) => updates(message as EngineGetGroupCallRequest)) as EngineGetGroupCallRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetGroupCallRequest create() => EngineGetGroupCallRequest._();
  EngineGetGroupCallRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetGroupCallRequest> createRepeated() => $pb.PbList<EngineGetGroupCallRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetGroupCallRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetGroupCallRequest>(create);
  static EngineGetGroupCallRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class EngineGetGroupCallResponse extends $pb.GeneratedMessage {
  factory EngineGetGroupCallResponse({
    EngineGroupCallInfo? groupCall,
  }) {
    final $result = create();
    if (groupCall != null) {
      $result.groupCall = groupCall;
    }
    return $result;
  }
  EngineGetGroupCallResponse._() : super();
  factory EngineGetGroupCallResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetGroupCallResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetGroupCallResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOM<EngineGroupCallInfo>(1, _omitFieldNames ? '' : 'groupCall', subBuilder: EngineGroupCallInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetGroupCallResponse clone() => EngineGetGroupCallResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetGroupCallResponse copyWith(void Function(EngineGetGroupCallResponse) updates) => super.copyWith((message) => updates(message as EngineGetGroupCallResponse)) as EngineGetGroupCallResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetGroupCallResponse create() => EngineGetGroupCallResponse._();
  EngineGetGroupCallResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetGroupCallResponse> createRepeated() => $pb.PbList<EngineGetGroupCallResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetGroupCallResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetGroupCallResponse>(create);
  static EngineGetGroupCallResponse? _defaultInstance;

  @$pb.TagNumber(1)
  EngineGroupCallInfo get groupCall => $_getN(0);
  @$pb.TagNumber(1)
  set groupCall(EngineGroupCallInfo v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasGroupCall() => $_has(0);
  @$pb.TagNumber(1)
  void clearGroupCall() => clearField(1);
  @$pb.TagNumber(1)
  EngineGroupCallInfo ensureGroupCall() => $_ensure(0);
}

class EngineJoinGroupCallRequest extends $pb.GeneratedMessage {
  factory EngineJoinGroupCallRequest({
    $core.String? accountId,
    $core.String? chatId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    return $result;
  }
  EngineJoinGroupCallRequest._() : super();
  factory EngineJoinGroupCallRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineJoinGroupCallRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineJoinGroupCallRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineJoinGroupCallRequest clone() => EngineJoinGroupCallRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineJoinGroupCallRequest copyWith(void Function(EngineJoinGroupCallRequest) updates) => super.copyWith((message) => updates(message as EngineJoinGroupCallRequest)) as EngineJoinGroupCallRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineJoinGroupCallRequest create() => EngineJoinGroupCallRequest._();
  EngineJoinGroupCallRequest createEmptyInstance() => create();
  static $pb.PbList<EngineJoinGroupCallRequest> createRepeated() => $pb.PbList<EngineJoinGroupCallRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineJoinGroupCallRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineJoinGroupCallRequest>(create);
  static EngineJoinGroupCallRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class EngineJoinGroupCallResponse extends $pb.GeneratedMessage {
  factory EngineJoinGroupCallResponse({
    $core.String? callId,
  }) {
    final $result = create();
    if (callId != null) {
      $result.callId = callId;
    }
    return $result;
  }
  EngineJoinGroupCallResponse._() : super();
  factory EngineJoinGroupCallResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineJoinGroupCallResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineJoinGroupCallResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'callId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineJoinGroupCallResponse clone() => EngineJoinGroupCallResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineJoinGroupCallResponse copyWith(void Function(EngineJoinGroupCallResponse) updates) => super.copyWith((message) => updates(message as EngineJoinGroupCallResponse)) as EngineJoinGroupCallResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineJoinGroupCallResponse create() => EngineJoinGroupCallResponse._();
  EngineJoinGroupCallResponse createEmptyInstance() => create();
  static $pb.PbList<EngineJoinGroupCallResponse> createRepeated() => $pb.PbList<EngineJoinGroupCallResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineJoinGroupCallResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineJoinGroupCallResponse>(create);
  static EngineJoinGroupCallResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get callId => $_getSZ(0);
  @$pb.TagNumber(1)
  set callId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasCallId() => $_has(0);
  @$pb.TagNumber(1)
  void clearCallId() => clearField(1);
}

class EngineSendScheduledNowRequest extends $pb.GeneratedMessage {
  factory EngineSendScheduledNowRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.Iterable<$core.String>? msgIds,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgIds != null) {
      $result.msgIds.addAll(msgIds);
    }
    return $result;
  }
  EngineSendScheduledNowRequest._() : super();
  factory EngineSendScheduledNowRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSendScheduledNowRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSendScheduledNowRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..pPS(3, _omitFieldNames ? '' : 'msgIds')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineSendScheduledNowRequest clone() => EngineSendScheduledNowRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineSendScheduledNowRequest copyWith(void Function(EngineSendScheduledNowRequest) updates) => super.copyWith((message) => updates(message as EngineSendScheduledNowRequest)) as EngineSendScheduledNowRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSendScheduledNowRequest create() => EngineSendScheduledNowRequest._();
  EngineSendScheduledNowRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSendScheduledNowRequest> createRepeated() => $pb.PbList<EngineSendScheduledNowRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSendScheduledNowRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSendScheduledNowRequest>(create);
  static EngineSendScheduledNowRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.String> get msgIds => $_getList(2);
}

class EngineRescheduleMessageRequest extends $pb.GeneratedMessage {
  factory EngineRescheduleMessageRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $fixnum.Int64? scheduleDate,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (scheduleDate != null) {
      $result.scheduleDate = scheduleDate;
    }
    return $result;
  }
  EngineRescheduleMessageRequest._() : super();
  factory EngineRescheduleMessageRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineRescheduleMessageRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineRescheduleMessageRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..aInt64(4, _omitFieldNames ? '' : 'scheduleDate')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineRescheduleMessageRequest clone() => EngineRescheduleMessageRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineRescheduleMessageRequest copyWith(void Function(EngineRescheduleMessageRequest) updates) => super.copyWith((message) => updates(message as EngineRescheduleMessageRequest)) as EngineRescheduleMessageRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineRescheduleMessageRequest create() => EngineRescheduleMessageRequest._();
  EngineRescheduleMessageRequest createEmptyInstance() => create();
  static $pb.PbList<EngineRescheduleMessageRequest> createRepeated() => $pb.PbList<EngineRescheduleMessageRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineRescheduleMessageRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineRescheduleMessageRequest>(create);
  static EngineRescheduleMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get scheduleDate => $_getI64(3);
  @$pb.TagNumber(4)
  set scheduleDate($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasScheduleDate() => $_has(3);
  @$pb.TagNumber(4)
  void clearScheduleDate() => clearField(4);
}

class EnginePeerColorEntry extends $pb.GeneratedMessage {
  factory EnginePeerColorEntry({
    $core.int? colorId,
    $core.Iterable<$core.int>? dayColors,
    $core.Iterable<$core.int>? nightColors,
    $core.bool? hidden,
  }) {
    final $result = create();
    if (colorId != null) {
      $result.colorId = colorId;
    }
    if (dayColors != null) {
      $result.dayColors.addAll(dayColors);
    }
    if (nightColors != null) {
      $result.nightColors.addAll(nightColors);
    }
    if (hidden != null) {
      $result.hidden = hidden;
    }
    return $result;
  }
  EnginePeerColorEntry._() : super();
  factory EnginePeerColorEntry.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EnginePeerColorEntry.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EnginePeerColorEntry', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'colorId', $pb.PbFieldType.O3)
    ..p<$core.int>(2, _omitFieldNames ? '' : 'dayColors', $pb.PbFieldType.K3)
    ..p<$core.int>(3, _omitFieldNames ? '' : 'nightColors', $pb.PbFieldType.K3)
    ..aOB(4, _omitFieldNames ? '' : 'hidden')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EnginePeerColorEntry clone() => EnginePeerColorEntry()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EnginePeerColorEntry copyWith(void Function(EnginePeerColorEntry) updates) => super.copyWith((message) => updates(message as EnginePeerColorEntry)) as EnginePeerColorEntry;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EnginePeerColorEntry create() => EnginePeerColorEntry._();
  EnginePeerColorEntry createEmptyInstance() => create();
  static $pb.PbList<EnginePeerColorEntry> createRepeated() => $pb.PbList<EnginePeerColorEntry>();
  @$core.pragma('dart2js:noInline')
  static EnginePeerColorEntry getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EnginePeerColorEntry>(create);
  static EnginePeerColorEntry? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get colorId => $_getIZ(0);
  @$pb.TagNumber(1)
  set colorId($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasColorId() => $_has(0);
  @$pb.TagNumber(1)
  void clearColorId() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get dayColors => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<$core.int> get nightColors => $_getList(2);

  @$pb.TagNumber(4)
  $core.bool get hidden => $_getBF(3);
  @$pb.TagNumber(4)
  set hidden($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasHidden() => $_has(3);
  @$pb.TagNumber(4)
  void clearHidden() => clearField(4);
}

class EngineGetPeerColorsRequest extends $pb.GeneratedMessage {
  factory EngineGetPeerColorsRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    return $result;
  }
  EngineGetPeerColorsRequest._() : super();
  factory EngineGetPeerColorsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetPeerColorsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetPeerColorsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetPeerColorsRequest clone() => EngineGetPeerColorsRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetPeerColorsRequest copyWith(void Function(EngineGetPeerColorsRequest) updates) => super.copyWith((message) => updates(message as EngineGetPeerColorsRequest)) as EngineGetPeerColorsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetPeerColorsRequest create() => EngineGetPeerColorsRequest._();
  EngineGetPeerColorsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetPeerColorsRequest> createRepeated() => $pb.PbList<EngineGetPeerColorsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetPeerColorsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetPeerColorsRequest>(create);
  static EngineGetPeerColorsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);
}

class EngineGetPeerColorsResponse extends $pb.GeneratedMessage {
  factory EngineGetPeerColorsResponse({
    $core.Iterable<EnginePeerColorEntry>? colors,
  }) {
    final $result = create();
    if (colors != null) {
      $result.colors.addAll(colors);
    }
    return $result;
  }
  EngineGetPeerColorsResponse._() : super();
  factory EngineGetPeerColorsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetPeerColorsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetPeerColorsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EnginePeerColorEntry>(1, _omitFieldNames ? '' : 'colors', $pb.PbFieldType.PM, subBuilder: EnginePeerColorEntry.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EngineGetPeerColorsResponse clone() => EngineGetPeerColorsResponse()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EngineGetPeerColorsResponse copyWith(void Function(EngineGetPeerColorsResponse) updates) => super.copyWith((message) => updates(message as EngineGetPeerColorsResponse)) as EngineGetPeerColorsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetPeerColorsResponse create() => EngineGetPeerColorsResponse._();
  EngineGetPeerColorsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetPeerColorsResponse> createRepeated() => $pb.PbList<EngineGetPeerColorsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetPeerColorsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetPeerColorsResponse>(create);
  static EngineGetPeerColorsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EnginePeerColorEntry> get colors => $_getList(0);
}

class EngineGetStickerSetInfoRequest extends $pb.GeneratedMessage {
  factory EngineGetStickerSetInfoRequest({
    $core.String? accountId,
    $core.String? shortName,
    $fixnum.Int64? setId,
    $fixnum.Int64? accessHash,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (shortName != null) $result.shortName = shortName;
    if (setId != null) $result.setId = setId;
    if (accessHash != null) $result.accessHash = accessHash;
    return $result;
  }
  EngineGetStickerSetInfoRequest._() : super();
  factory EngineGetStickerSetInfoRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetStickerSetInfoRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetStickerSetInfoRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'shortName')
    ..aInt64(3, _omitFieldNames ? '' : 'setId')
    ..aInt64(4, _omitFieldNames ? '' : 'accessHash')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetStickerSetInfoRequest clone() => EngineGetStickerSetInfoRequest()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineGetStickerSetInfoRequest copyWith(void Function(EngineGetStickerSetInfoRequest) updates) => super.copyWith((message) => updates(message as EngineGetStickerSetInfoRequest)) as EngineGetStickerSetInfoRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetStickerSetInfoRequest create() => EngineGetStickerSetInfoRequest._();
  EngineGetStickerSetInfoRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetStickerSetInfoRequest> createRepeated() => $pb.PbList<EngineGetStickerSetInfoRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetStickerSetInfoRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetStickerSetInfoRequest>(create);
  static EngineGetStickerSetInfoRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get shortName => $_getSZ(1);
  @$pb.TagNumber(2)
  set shortName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasShortName() => $_has(1);
  @$pb.TagNumber(2)
  void clearShortName() => clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get setId => $_getI64(2);
  @$pb.TagNumber(3)
  set setId($fixnum.Int64 v) { $_setInt64(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSetId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSetId() => clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get accessHash => $_getI64(3);
  @$pb.TagNumber(4)
  set accessHash($fixnum.Int64 v) { $_setInt64(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasAccessHash() => $_has(3);
  @$pb.TagNumber(4)
  void clearAccessHash() => clearField(4);
}

class EngineStickerInfo extends $pb.GeneratedMessage {
  factory EngineStickerInfo({
    $core.String? emoji,
    $core.String? thumbB64,
    $core.int? width,
    $core.int? height,
    $core.String? mimeType,
    $core.String? fileId,
  }) {
    final $result = create();
    if (emoji != null) $result.emoji = emoji;
    if (thumbB64 != null) $result.thumbB64 = thumbB64;
    if (width != null) $result.width = width;
    if (height != null) $result.height = height;
    if (mimeType != null) $result.mimeType = mimeType;
    if (fileId != null) $result.fileId = fileId;
    return $result;
  }
  EngineStickerInfo._() : super();
  factory EngineStickerInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineStickerInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineStickerInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'emoji')
    ..aOS(2, _omitFieldNames ? '' : 'thumbB64')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'height', $pb.PbFieldType.O3)
    ..aOS(5, _omitFieldNames ? '' : 'mimeType')
    ..aOS(6, _omitFieldNames ? '' : 'fileId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineStickerInfo clone() => EngineStickerInfo()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineStickerInfo copyWith(void Function(EngineStickerInfo) updates) => super.copyWith((message) => updates(message as EngineStickerInfo)) as EngineStickerInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineStickerInfo create() => EngineStickerInfo._();
  EngineStickerInfo createEmptyInstance() => create();
  static $pb.PbList<EngineStickerInfo> createRepeated() => $pb.PbList<EngineStickerInfo>();
  @$core.pragma('dart2js:noInline')
  static EngineStickerInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineStickerInfo>(create);
  static EngineStickerInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get emoji => $_getSZ(0);
  @$pb.TagNumber(1)
  set emoji($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get thumbB64 => $_getSZ(1);
  @$pb.TagNumber(2)
  set thumbB64($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.int get width => $_getIZ(2);
  @$pb.TagNumber(3)
  set width($core.int v) { $_setSignedInt32(2, v); }

  @$pb.TagNumber(4)
  $core.int get height => $_getIZ(3);
  @$pb.TagNumber(4)
  set height($core.int v) { $_setSignedInt32(3, v); }

  @$pb.TagNumber(5)
  $core.String get mimeType => $_getSZ(4);
  @$pb.TagNumber(5)
  set mimeType($core.String v) { $_setString(4, v); }

  @$pb.TagNumber(6)
  $core.String get fileId => $_getSZ(5);
  @$pb.TagNumber(6)
  set fileId($core.String v) { $_setString(5, v); }
}

class EngineGetStickerSetInfoResponse extends $pb.GeneratedMessage {
  factory EngineGetStickerSetInfoResponse({
    $core.String? title,
    $core.String? shortName,
    $core.int? count,
    $core.bool? installed,
    $core.bool? archived,
    $core.bool? animated,
    $core.bool? video,
    $core.Iterable<EngineStickerInfo>? stickers,
  }) {
    final $result = create();
    if (title != null) $result.title = title;
    if (shortName != null) $result.shortName = shortName;
    if (count != null) $result.count = count;
    if (installed != null) $result.installed = installed;
    if (archived != null) $result.archived = archived;
    if (animated != null) $result.animated = animated;
    if (video != null) $result.video = video;
    if (stickers != null) $result.stickers.addAll(stickers);
    return $result;
  }
  EngineGetStickerSetInfoResponse._() : super();
  factory EngineGetStickerSetInfoResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetStickerSetInfoResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetStickerSetInfoResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'title')
    ..aOS(2, _omitFieldNames ? '' : 'shortName')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'count', $pb.PbFieldType.O3)
    ..aOB(4, _omitFieldNames ? '' : 'installed')
    ..aOB(5, _omitFieldNames ? '' : 'archived')
    ..aOB(6, _omitFieldNames ? '' : 'animated')
    ..aOB(7, _omitFieldNames ? '' : 'video')
    ..pc<EngineStickerInfo>(8, _omitFieldNames ? '' : 'stickers', $pb.PbFieldType.PM, subBuilder: EngineStickerInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetStickerSetInfoResponse clone() => EngineGetStickerSetInfoResponse()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineGetStickerSetInfoResponse copyWith(void Function(EngineGetStickerSetInfoResponse) updates) => super.copyWith((message) => updates(message as EngineGetStickerSetInfoResponse)) as EngineGetStickerSetInfoResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetStickerSetInfoResponse create() => EngineGetStickerSetInfoResponse._();
  EngineGetStickerSetInfoResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetStickerSetInfoResponse> createRepeated() => $pb.PbList<EngineGetStickerSetInfoResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetStickerSetInfoResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetStickerSetInfoResponse>(create);
  static EngineGetStickerSetInfoResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get title => $_getSZ(0);
  @$pb.TagNumber(1)
  set title($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get shortName => $_getSZ(1);
  @$pb.TagNumber(2)
  set shortName($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.int get count => $_getIZ(2);
  @$pb.TagNumber(3)
  set count($core.int v) { $_setSignedInt32(2, v); }

  @$pb.TagNumber(4)
  $core.bool get installed => $_getBF(3);
  @$pb.TagNumber(4)
  set installed($core.bool v) { $_setBool(3, v); }

  @$pb.TagNumber(5)
  $core.bool get archived => $_getBF(4);
  @$pb.TagNumber(5)
  set archived($core.bool v) { $_setBool(4, v); }

  @$pb.TagNumber(6)
  $core.bool get animated => $_getBF(5);
  @$pb.TagNumber(6)
  set animated($core.bool v) { $_setBool(5, v); }

  @$pb.TagNumber(7)
  $core.bool get video => $_getBF(6);
  @$pb.TagNumber(7)
  set video($core.bool v) { $_setBool(6, v); }

  @$pb.TagNumber(8)
  $core.List<EngineStickerInfo> get stickers => $_getList(7);
}

// ═══════════════════════════════════════════════════════════════════════
// Voice Transcription
// ═══════════════════════════════════════════════════════════════════════

class EngineTranscribeAudioRequest extends $pb.GeneratedMessage {
  factory EngineTranscribeAudioRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (msgId != null) $result.msgId = msgId;
    return $result;
  }
  EngineTranscribeAudioRequest._() : super();
  factory EngineTranscribeAudioRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineTranscribeAudioRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineTranscribeAudioRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineTranscribeAudioRequest clone() => EngineTranscribeAudioRequest()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineTranscribeAudioRequest copyWith(void Function(EngineTranscribeAudioRequest) updates) => super.copyWith((message) => updates(message as EngineTranscribeAudioRequest)) as EngineTranscribeAudioRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineTranscribeAudioRequest create() => EngineTranscribeAudioRequest._();
  EngineTranscribeAudioRequest createEmptyInstance() => create();
  static $pb.PbList<EngineTranscribeAudioRequest> createRepeated() => $pb.PbList<EngineTranscribeAudioRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineTranscribeAudioRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineTranscribeAudioRequest>(create);
  static EngineTranscribeAudioRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
}

class EngineTranscribeAudioResponse extends $pb.GeneratedMessage {
  factory EngineTranscribeAudioResponse({
    $core.bool? pending,
    $fixnum.Int64? transcriptionId,
    $core.String? text,
  }) {
    final $result = create();
    if (pending != null) $result.pending = pending;
    if (transcriptionId != null) $result.transcriptionId = transcriptionId;
    if (text != null) $result.text = text;
    return $result;
  }
  EngineTranscribeAudioResponse._() : super();
  factory EngineTranscribeAudioResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineTranscribeAudioResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineTranscribeAudioResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'pending')
    ..aInt64(2, _omitFieldNames ? '' : 'transcriptionId')
    ..aOS(3, _omitFieldNames ? '' : 'text')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineTranscribeAudioResponse clone() => EngineTranscribeAudioResponse()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineTranscribeAudioResponse copyWith(void Function(EngineTranscribeAudioResponse) updates) => super.copyWith((message) => updates(message as EngineTranscribeAudioResponse)) as EngineTranscribeAudioResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineTranscribeAudioResponse create() => EngineTranscribeAudioResponse._();
  EngineTranscribeAudioResponse createEmptyInstance() => create();
  static $pb.PbList<EngineTranscribeAudioResponse> createRepeated() => $pb.PbList<EngineTranscribeAudioResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineTranscribeAudioResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineTranscribeAudioResponse>(create);
  static EngineTranscribeAudioResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get pending => $_getBF(0);
  @$pb.TagNumber(1)
  set pending($core.bool v) { $_setBool(0, v); }

  @$pb.TagNumber(2)
  $fixnum.Int64 get transcriptionId => $_getI64(1);
  @$pb.TagNumber(2)
  set transcriptionId($fixnum.Int64 v) { $_setInt64(1, v); }

  @$pb.TagNumber(3)
  $core.String get text => $_getSZ(2);
  @$pb.TagNumber(3)
  set text($core.String v) { $_setString(2, v); }
}


class EngineGetAttachMenuBotsRequest extends $pb.GeneratedMessage {
  factory EngineGetAttachMenuBotsRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    return $result;
  }
  EngineGetAttachMenuBotsRequest._() : super();
  factory EngineGetAttachMenuBotsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetAttachMenuBotsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetAttachMenuBotsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetAttachMenuBotsRequest clone() => EngineGetAttachMenuBotsRequest()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineGetAttachMenuBotsRequest copyWith(void Function(EngineGetAttachMenuBotsRequest) updates) => super.copyWith((message) => updates(message as EngineGetAttachMenuBotsRequest)) as EngineGetAttachMenuBotsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetAttachMenuBotsRequest create() => EngineGetAttachMenuBotsRequest._();
  EngineGetAttachMenuBotsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetAttachMenuBotsRequest> createRepeated() => $pb.PbList<EngineGetAttachMenuBotsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetAttachMenuBotsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetAttachMenuBotsRequest>(create);
  static EngineGetAttachMenuBotsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
}

class EngineAttachMenuBotInfo extends $pb.GeneratedMessage {
  factory EngineAttachMenuBotInfo({
    $fixnum.Int64? botId,
    $core.String? shortName,
    $core.bool? inactive,
  }) {
    final $result = create();
    if (botId != null) $result.botId = botId;
    if (shortName != null) $result.shortName = shortName;
    if (inactive != null) $result.inactive = inactive;
    return $result;
  }
  EngineAttachMenuBotInfo._() : super();
  factory EngineAttachMenuBotInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineAttachMenuBotInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineAttachMenuBotInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'botId')
    ..aOS(2, _omitFieldNames ? '' : 'shortName')
    ..aOB(3, _omitFieldNames ? '' : 'inactive')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineAttachMenuBotInfo clone() => EngineAttachMenuBotInfo()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineAttachMenuBotInfo copyWith(void Function(EngineAttachMenuBotInfo) updates) => super.copyWith((message) => updates(message as EngineAttachMenuBotInfo)) as EngineAttachMenuBotInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineAttachMenuBotInfo create() => EngineAttachMenuBotInfo._();
  EngineAttachMenuBotInfo createEmptyInstance() => create();
  static $pb.PbList<EngineAttachMenuBotInfo> createRepeated() => $pb.PbList<EngineAttachMenuBotInfo>();
  @$core.pragma('dart2js:noInline')
  static EngineAttachMenuBotInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineAttachMenuBotInfo>(create);
  static EngineAttachMenuBotInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get botId => $_getI64(0);
  @$pb.TagNumber(1)
  set botId($fixnum.Int64 v) { $_setInt64(0, v); }

  @$pb.TagNumber(2)
  $core.String get shortName => $_getSZ(1);
  @$pb.TagNumber(2)
  set shortName($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.bool get inactive => $_getBF(2);
  @$pb.TagNumber(3)
  set inactive($core.bool v) { $_setBool(2, v); }
}

class EngineGetAttachMenuBotsResponse extends $pb.GeneratedMessage {
  factory EngineGetAttachMenuBotsResponse({
    $core.Iterable<EngineAttachMenuBotInfo>? bots,
  }) {
    final $result = create();
    if (bots != null) $result.bots.addAll(bots);
    return $result;
  }
  EngineGetAttachMenuBotsResponse._() : super();
  factory EngineGetAttachMenuBotsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetAttachMenuBotsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetAttachMenuBotsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineAttachMenuBotInfo>(1, _omitFieldNames ? '' : 'bots', $pb.PbFieldType.PM, subBuilder: EngineAttachMenuBotInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetAttachMenuBotsResponse clone() => EngineGetAttachMenuBotsResponse()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineGetAttachMenuBotsResponse copyWith(void Function(EngineGetAttachMenuBotsResponse) updates) => super.copyWith((message) => updates(message as EngineGetAttachMenuBotsResponse)) as EngineGetAttachMenuBotsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetAttachMenuBotsResponse create() => EngineGetAttachMenuBotsResponse._();
  EngineGetAttachMenuBotsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetAttachMenuBotsResponse> createRepeated() => $pb.PbList<EngineGetAttachMenuBotsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetAttachMenuBotsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetAttachMenuBotsResponse>(create);
  static EngineGetAttachMenuBotsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineAttachMenuBotInfo> get bots => $_getList(0);
}

class EngineGetWebPagePreviewRequest extends $pb.GeneratedMessage {
  factory EngineGetWebPagePreviewRequest({
    $core.String? accountId,
    $core.String? url,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (url != null) $result.url = url;
    return $result;
  }
  EngineGetWebPagePreviewRequest._() : super();
  factory EngineGetWebPagePreviewRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetWebPagePreviewRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetWebPagePreviewRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'url')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetWebPagePreviewRequest clone() => EngineGetWebPagePreviewRequest()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineGetWebPagePreviewRequest copyWith(void Function(EngineGetWebPagePreviewRequest) updates) => super.copyWith((message) => updates(message as EngineGetWebPagePreviewRequest)) as EngineGetWebPagePreviewRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetWebPagePreviewRequest create() => EngineGetWebPagePreviewRequest._();
  EngineGetWebPagePreviewRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetWebPagePreviewRequest> createRepeated() => $pb.PbList<EngineGetWebPagePreviewRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetWebPagePreviewRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetWebPagePreviewRequest>(create);
  static EngineGetWebPagePreviewRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get url => $_getSZ(1);
  @$pb.TagNumber(2)
  set url($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasUrl() => $_has(1);
  @$pb.TagNumber(2)
  void clearUrl() => clearField(2);
}

class EngineGetWebPagePreviewResponse extends $pb.GeneratedMessage {
  factory EngineGetWebPagePreviewResponse({
    $core.String? url,
    $core.String? siteName,
    $core.String? title,
    $core.String? description,
    $core.String? thumbB64,
  }) {
    final $result = create();
    if (url != null) $result.url = url;
    if (siteName != null) $result.siteName = siteName;
    if (title != null) $result.title = title;
    if (description != null) $result.description = description;
    if (thumbB64 != null) $result.thumbB64 = thumbB64;
    return $result;
  }
  EngineGetWebPagePreviewResponse._() : super();
  factory EngineGetWebPagePreviewResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetWebPagePreviewResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetWebPagePreviewResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'url')
    ..aOS(2, _omitFieldNames ? '' : 'siteName')
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..aOS(4, _omitFieldNames ? '' : 'description')
    ..aOS(5, _omitFieldNames ? '' : 'thumbB64')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetWebPagePreviewResponse clone() => EngineGetWebPagePreviewResponse()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineGetWebPagePreviewResponse copyWith(void Function(EngineGetWebPagePreviewResponse) updates) => super.copyWith((message) => updates(message as EngineGetWebPagePreviewResponse)) as EngineGetWebPagePreviewResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetWebPagePreviewResponse create() => EngineGetWebPagePreviewResponse._();
  EngineGetWebPagePreviewResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetWebPagePreviewResponse> createRepeated() => $pb.PbList<EngineGetWebPagePreviewResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetWebPagePreviewResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetWebPagePreviewResponse>(create);
  static EngineGetWebPagePreviewResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get url => $_getSZ(0);
  @$pb.TagNumber(1)
  set url($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasUrl() => $_has(0);
  @$pb.TagNumber(1)
  void clearUrl() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get siteName => $_getSZ(1);
  @$pb.TagNumber(2)
  set siteName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSiteName() => $_has(1);
  @$pb.TagNumber(2)
  void clearSiteName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTitle() => $_has(2);
  @$pb.TagNumber(3)
  void clearTitle() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get description => $_getSZ(3);
  @$pb.TagNumber(4)
  set description($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasDescription() => $_has(3);
  @$pb.TagNumber(4)
  void clearDescription() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get thumbB64 => $_getSZ(4);
  @$pb.TagNumber(5)
  set thumbB64($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasThumbB64() => $_has(4);
  @$pb.TagNumber(5)
  void clearThumbB64() => clearField(5);
}

class EngineBotCallbackRequest extends $pb.GeneratedMessage {
  factory EngineBotCallbackRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.String? data,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (chatId != null) {
      $result.chatId = chatId;
    }
    if (msgId != null) {
      $result.msgId = msgId;
    }
    if (data != null) {
      $result.data = data;
    }
    return $result;
  }
  EngineBotCallbackRequest._() : super();
  factory EngineBotCallbackRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineBotCallbackRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineBotCallbackRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..aOS(4, _omitFieldNames ? '' : 'data')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineBotCallbackRequest clone() => EngineBotCallbackRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineBotCallbackRequest copyWith(void Function(EngineBotCallbackRequest) updates) => super.copyWith((message) => updates(message as EngineBotCallbackRequest)) as EngineBotCallbackRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineBotCallbackRequest create() => EngineBotCallbackRequest._();
  EngineBotCallbackRequest createEmptyInstance() => create();
  static $pb.PbList<EngineBotCallbackRequest> createRepeated() => $pb.PbList<EngineBotCallbackRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineBotCallbackRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineBotCallbackRequest>(create);
  static EngineBotCallbackRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMsgId() => $_has(2);
  @$pb.TagNumber(3)
  void clearMsgId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get data => $_getSZ(3);
  @$pb.TagNumber(4)
  set data($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasData() => $_has(3);
  @$pb.TagNumber(4)
  void clearData() => clearField(4);
}

class EngineBotCallbackResponse extends $pb.GeneratedMessage {
  factory EngineBotCallbackResponse({
    $core.String? message,
    $core.bool? showAlert,
    $core.String? url,
  }) {
    final $result = create();
    if (message != null) {
      $result.message = message;
    }
    if (showAlert != null) {
      $result.showAlert = showAlert;
    }
    if (url != null) {
      $result.url = url;
    }
    return $result;
  }
  EngineBotCallbackResponse._() : super();
  factory EngineBotCallbackResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineBotCallbackResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineBotCallbackResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'message')
    ..aOB(2, _omitFieldNames ? '' : 'showAlert')
    ..aOS(3, _omitFieldNames ? '' : 'url')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineBotCallbackResponse clone() => EngineBotCallbackResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineBotCallbackResponse copyWith(void Function(EngineBotCallbackResponse) updates) => super.copyWith((message) => updates(message as EngineBotCallbackResponse)) as EngineBotCallbackResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineBotCallbackResponse create() => EngineBotCallbackResponse._();
  EngineBotCallbackResponse createEmptyInstance() => create();
  static $pb.PbList<EngineBotCallbackResponse> createRepeated() => $pb.PbList<EngineBotCallbackResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineBotCallbackResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineBotCallbackResponse>(create);
  static EngineBotCallbackResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get message => $_getSZ(0);
  @$pb.TagNumber(1)
  set message($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMessage() => $_has(0);
  @$pb.TagNumber(1)
  void clearMessage() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get showAlert => $_getBF(1);
  @$pb.TagNumber(2)
  set showAlert($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasShowAlert() => $_has(1);
  @$pb.TagNumber(2)
  void clearShowAlert() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get url => $_getSZ(2);
  @$pb.TagNumber(3)
  set url($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUrl() => $_has(2);
  @$pb.TagNumber(3)
  void clearUrl() => clearField(3);
}

// ── Send As (channel sender identity selector) ──

class EngineGetSendAsRequest extends $pb.GeneratedMessage {
  factory EngineGetSendAsRequest({
    $core.String? accountId,
    $core.String? chatId,
  }) {
    final $result = create();
    if (accountId != null) { $result.accountId = accountId; }
    if (chatId != null) { $result.chatId = chatId; }
    return $result;
  }
  EngineGetSendAsRequest._() : super();
  factory EngineGetSendAsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetSendAsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSendAsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetSendAsRequest clone() => EngineGetSendAsRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetSendAsRequest copyWith(void Function(EngineGetSendAsRequest) updates) => super.copyWith((message) => updates(message as EngineGetSendAsRequest)) as EngineGetSendAsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSendAsRequest create() => EngineGetSendAsRequest._();
  EngineGetSendAsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetSendAsRequest> createRepeated() => $pb.PbList<EngineGetSendAsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSendAsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSendAsRequest>(create);
  static EngineGetSendAsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);
}

class EngineSendAsPeerInfo extends $pb.GeneratedMessage {
  factory EngineSendAsPeerInfo({
    $core.String? peerId,
    $core.String? displayName,
    $core.String? avatarPath,
    $core.bool? isChannel,
  }) {
    final $result = create();
    if (peerId != null) { $result.peerId = peerId; }
    if (displayName != null) { $result.displayName = displayName; }
    if (avatarPath != null) { $result.avatarPath = avatarPath; }
    if (isChannel != null) { $result.isChannel = isChannel; }
    return $result;
  }
  EngineSendAsPeerInfo._() : super();
  factory EngineSendAsPeerInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSendAsPeerInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSendAsPeerInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'peerId')
    ..aOS(2, _omitFieldNames ? '' : 'displayName')
    ..aOS(3, _omitFieldNames ? '' : 'avatarPath')
    ..aOB(4, _omitFieldNames ? '' : 'isChannel')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineSendAsPeerInfo clone() => EngineSendAsPeerInfo()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineSendAsPeerInfo copyWith(void Function(EngineSendAsPeerInfo) updates) => super.copyWith((message) => updates(message as EngineSendAsPeerInfo)) as EngineSendAsPeerInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSendAsPeerInfo create() => EngineSendAsPeerInfo._();
  EngineSendAsPeerInfo createEmptyInstance() => create();
  static $pb.PbList<EngineSendAsPeerInfo> createRepeated() => $pb.PbList<EngineSendAsPeerInfo>();
  @$core.pragma('dart2js:noInline')
  static EngineSendAsPeerInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSendAsPeerInfo>(create);
  static EngineSendAsPeerInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get peerId => $_getSZ(0);
  @$pb.TagNumber(1)
  set peerId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPeerId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPeerId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get displayName => $_getSZ(1);
  @$pb.TagNumber(2)
  set displayName($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDisplayName() => $_has(1);
  @$pb.TagNumber(2)
  void clearDisplayName() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get avatarPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set avatarPath($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasAvatarPath() => $_has(2);
  @$pb.TagNumber(3)
  void clearAvatarPath() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isChannel => $_getBF(3);
  @$pb.TagNumber(4)
  set isChannel($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsChannel() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsChannel() => clearField(4);
}

class EngineGetSendAsResponse extends $pb.GeneratedMessage {
  factory EngineGetSendAsResponse({
    $core.List<EngineSendAsPeerInfo>? peers,
  }) {
    final $result = create();
    if (peers != null) { $result.peers.addAll(peers); }
    return $result;
  }
  EngineGetSendAsResponse._() : super();
  factory EngineGetSendAsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetSendAsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSendAsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineSendAsPeerInfo>(1, _omitFieldNames ? '' : 'peers', $pb.PbFieldType.PM, subBuilder: EngineSendAsPeerInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetSendAsResponse clone() => EngineGetSendAsResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetSendAsResponse copyWith(void Function(EngineGetSendAsResponse) updates) => super.copyWith((message) => updates(message as EngineGetSendAsResponse)) as EngineGetSendAsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSendAsResponse create() => EngineGetSendAsResponse._();
  EngineGetSendAsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetSendAsResponse> createRepeated() => $pb.PbList<EngineGetSendAsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSendAsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSendAsResponse>(create);
  static EngineGetSendAsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineSendAsPeerInfo> get peers => $_getList(0);
}

class EngineSaveDefaultSendAsRequest extends $pb.GeneratedMessage {
  factory EngineSaveDefaultSendAsRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? peerId,
  }) {
    final $result = create();
    if (accountId != null) { $result.accountId = accountId; }
    if (chatId != null) { $result.chatId = chatId; }
    if (peerId != null) { $result.peerId = peerId; }
    return $result;
  }
  EngineSaveDefaultSendAsRequest._() : super();
  factory EngineSaveDefaultSendAsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSaveDefaultSendAsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSaveDefaultSendAsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'peerId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineSaveDefaultSendAsRequest clone() => EngineSaveDefaultSendAsRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineSaveDefaultSendAsRequest copyWith(void Function(EngineSaveDefaultSendAsRequest) updates) => super.copyWith((message) => updates(message as EngineSaveDefaultSendAsRequest)) as EngineSaveDefaultSendAsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSaveDefaultSendAsRequest create() => EngineSaveDefaultSendAsRequest._();
  EngineSaveDefaultSendAsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSaveDefaultSendAsRequest> createRepeated() => $pb.PbList<EngineSaveDefaultSendAsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSaveDefaultSendAsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSaveDefaultSendAsRequest>(create);
  static EngineSaveDefaultSendAsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccountId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);
  @$pb.TagNumber(2)
  void clearChatId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get peerId => $_getSZ(2);
  @$pb.TagNumber(3)
  set peerId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPeerId() => $_has(2);
  @$pb.TagNumber(3)
  void clearPeerId() => clearField(3);
}

class EngineSaveDefaultSendAsResponse extends $pb.GeneratedMessage {
  factory EngineSaveDefaultSendAsResponse({
    $core.bool? ok,
  }) {
    final $result = create();
    if (ok != null) { $result.ok = ok; }
    return $result;
  }
  EngineSaveDefaultSendAsResponse._() : super();
  factory EngineSaveDefaultSendAsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSaveDefaultSendAsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSaveDefaultSendAsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'ok')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineSaveDefaultSendAsResponse clone() => EngineSaveDefaultSendAsResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineSaveDefaultSendAsResponse copyWith(void Function(EngineSaveDefaultSendAsResponse) updates) => super.copyWith((message) => updates(message as EngineSaveDefaultSendAsResponse)) as EngineSaveDefaultSendAsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSaveDefaultSendAsResponse create() => EngineSaveDefaultSendAsResponse._();
  EngineSaveDefaultSendAsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineSaveDefaultSendAsResponse> createRepeated() => $pb.PbList<EngineSaveDefaultSendAsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineSaveDefaultSendAsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSaveDefaultSendAsResponse>(create);
  static EngineSaveDefaultSendAsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get ok => $_getBF(0);
  @$pb.TagNumber(1)
  set ok($core.bool v) { $_setBool(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOk() => $_has(0);
  @$pb.TagNumber(1)
  void clearOk() => clearField(1);
}

class EngineBanMemberRequest extends $pb.GeneratedMessage {
  factory EngineBanMemberRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? userId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (userId != null) $result.userId = userId;
    return $result;
  }
  EngineBanMemberRequest._() : super();
  factory EngineBanMemberRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineBanMemberRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineBanMemberRequest clone() => EngineBanMemberRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineBanMemberRequest copyWith(void Function(EngineBanMemberRequest) updates) => super.copyWith((message) => updates(message as EngineBanMemberRequest)) as EngineBanMemberRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineBanMemberRequest create() => EngineBanMemberRequest._();
  EngineBanMemberRequest createEmptyInstance() => create();
  static $pb.PbList<EngineBanMemberRequest> createRepeated() => $pb.PbList<EngineBanMemberRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineBanMemberRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineBanMemberRequest>(create);
  static EngineBanMemberRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);

  @$pb.TagNumber(3)
  $core.String get userId => $_getSZ(2);
  @$pb.TagNumber(3)
  set userId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUserId() => $_has(2);
}

class EngineRemoveMemberRequest extends $pb.GeneratedMessage {
  factory EngineRemoveMemberRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? userId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (userId != null) $result.userId = userId;
    return $result;
  }
  EngineRemoveMemberRequest._() : super();
  factory EngineRemoveMemberRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineRemoveMemberRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineRemoveMemberRequest clone() => EngineRemoveMemberRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineRemoveMemberRequest copyWith(void Function(EngineRemoveMemberRequest) updates) => super.copyWith((message) => updates(message as EngineRemoveMemberRequest)) as EngineRemoveMemberRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineRemoveMemberRequest create() => EngineRemoveMemberRequest._();
  EngineRemoveMemberRequest createEmptyInstance() => create();
  static $pb.PbList<EngineRemoveMemberRequest> createRepeated() => $pb.PbList<EngineRemoveMemberRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineRemoveMemberRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineRemoveMemberRequest>(create);
  static EngineRemoveMemberRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);

  @$pb.TagNumber(3)
  $core.String get userId => $_getSZ(2);
  @$pb.TagNumber(3)
  set userId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUserId() => $_has(2);
}

class EngineDemoteAdminRequest extends $pb.GeneratedMessage {
  factory EngineDemoteAdminRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? userId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (userId != null) $result.userId = userId;
    return $result;
  }
  EngineDemoteAdminRequest._() : super();
  factory EngineDemoteAdminRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineDemoteAdminRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineDemoteAdminRequest clone() => EngineDemoteAdminRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineDemoteAdminRequest copyWith(void Function(EngineDemoteAdminRequest) updates) => super.copyWith((message) => updates(message as EngineDemoteAdminRequest)) as EngineDemoteAdminRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineDemoteAdminRequest create() => EngineDemoteAdminRequest._();
  EngineDemoteAdminRequest createEmptyInstance() => create();
  static $pb.PbList<EngineDemoteAdminRequest> createRepeated() => $pb.PbList<EngineDemoteAdminRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineDemoteAdminRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineDemoteAdminRequest>(create);
  static EngineDemoteAdminRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);

  @$pb.TagNumber(3)
  $core.String get userId => $_getSZ(2);
  @$pb.TagNumber(3)
  set userId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUserId() => $_has(2);
}

class EnginePromoteAdminRequest extends $pb.GeneratedMessage {
  factory EnginePromoteAdminRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? userId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (userId != null) $result.userId = userId;
    return $result;
  }
  EnginePromoteAdminRequest._() : super();
  factory EnginePromoteAdminRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EnginePromoteAdminRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EnginePromoteAdminRequest clone() => EnginePromoteAdminRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EnginePromoteAdminRequest copyWith(void Function(EnginePromoteAdminRequest) updates) => super.copyWith((message) => updates(message as EnginePromoteAdminRequest)) as EnginePromoteAdminRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EnginePromoteAdminRequest create() => EnginePromoteAdminRequest._();
  EnginePromoteAdminRequest createEmptyInstance() => create();
  static $pb.PbList<EnginePromoteAdminRequest> createRepeated() => $pb.PbList<EnginePromoteAdminRequest>();
  @$core.pragma('dart2js:noInline')
  static EnginePromoteAdminRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EnginePromoteAdminRequest>(create);
  static EnginePromoteAdminRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);

  @$pb.TagNumber(3)
  $core.String get userId => $_getSZ(2);
  @$pb.TagNumber(3)
  set userId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUserId() => $_has(2);
}

class EngineRestrictMemberRequest extends $pb.GeneratedMessage {
  factory EngineRestrictMemberRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? userId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (userId != null) $result.userId = userId;
    return $result;
  }
  EngineRestrictMemberRequest._() : super();
  factory EngineRestrictMemberRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineRestrictMemberRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'userId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineRestrictMemberRequest clone() => EngineRestrictMemberRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineRestrictMemberRequest copyWith(void Function(EngineRestrictMemberRequest) updates) => super.copyWith((message) => updates(message as EngineRestrictMemberRequest)) as EngineRestrictMemberRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineRestrictMemberRequest create() => EngineRestrictMemberRequest._();
  EngineRestrictMemberRequest createEmptyInstance() => create();
  static $pb.PbList<EngineRestrictMemberRequest> createRepeated() => $pb.PbList<EngineRestrictMemberRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineRestrictMemberRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineRestrictMemberRequest>(create);
  static EngineRestrictMemberRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAccountId() => $_has(0);

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasChatId() => $_has(1);

  @$pb.TagNumber(3)
  $core.String get userId => $_getSZ(2);
  @$pb.TagNumber(3)
  set userId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasUserId() => $_has(2);
}

class EngineFaveStickerRequest extends $pb.GeneratedMessage {
  factory EngineFaveStickerRequest({
    $core.String? accountId,
    $fixnum.Int64? fileId,
    $core.bool? unfave,
    $core.String? extra,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (fileId != null) $result.fileId = fileId;
    if (unfave != null) $result.unfave = unfave;
    if (extra != null) $result.extra = extra;
    return $result;
  }
  EngineFaveStickerRequest._() : super();
  factory EngineFaveStickerRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineFaveStickerRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineFaveStickerRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aInt64(2, _omitFieldNames ? '' : 'fileId')
    ..aOB(3, _omitFieldNames ? '' : 'unfave')
    ..aOS(4, _omitFieldNames ? '' : 'extra')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineFaveStickerRequest clone() => EngineFaveStickerRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineFaveStickerRequest copyWith(void Function(EngineFaveStickerRequest) updates) => super.copyWith((message) => updates(message as EngineFaveStickerRequest)) as EngineFaveStickerRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineFaveStickerRequest create() => EngineFaveStickerRequest._();
  EngineFaveStickerRequest createEmptyInstance() => create();
  static $pb.PbList<EngineFaveStickerRequest> createRepeated() => $pb.PbList<EngineFaveStickerRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineFaveStickerRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineFaveStickerRequest>(create);
  static EngineFaveStickerRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $fixnum.Int64 get fileId => $_getI64(1);
  @$pb.TagNumber(2)
  set fileId($fixnum.Int64 v) { $_setInt64(1, v); }

  @$pb.TagNumber(3)
  $core.bool get unfave => $_getBF(2);
  @$pb.TagNumber(3)
  set unfave($core.bool v) { $_setBool(2, v); }

  @$pb.TagNumber(4)
  $core.String get extra => $_getSZ(3);
  @$pb.TagNumber(4)
  set extra($core.String v) { $_setString(3, v); }
}

class EngineSaveGifRequest extends $pb.GeneratedMessage {
  factory EngineSaveGifRequest({
    $core.String? accountId,
    $fixnum.Int64? fileId,
    $core.bool? unsave,
    $core.String? extra,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (fileId != null) $result.fileId = fileId;
    if (unsave != null) $result.unsave = unsave;
    if (extra != null) $result.extra = extra;
    return $result;
  }
  EngineSaveGifRequest._() : super();
  factory EngineSaveGifRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineSaveGifRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSaveGifRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aInt64(2, _omitFieldNames ? '' : 'fileId')
    ..aOB(3, _omitFieldNames ? '' : 'unsave')
    ..aOS(4, _omitFieldNames ? '' : 'extra')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineSaveGifRequest clone() => EngineSaveGifRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineSaveGifRequest copyWith(void Function(EngineSaveGifRequest) updates) => super.copyWith((message) => updates(message as EngineSaveGifRequest)) as EngineSaveGifRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineSaveGifRequest create() => EngineSaveGifRequest._();
  EngineSaveGifRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSaveGifRequest> createRepeated() => $pb.PbList<EngineSaveGifRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSaveGifRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSaveGifRequest>(create);
  static EngineSaveGifRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $fixnum.Int64 get fileId => $_getI64(1);
  @$pb.TagNumber(2)
  set fileId($fixnum.Int64 v) { $_setInt64(1, v); }

  @$pb.TagNumber(3)
  $core.bool get unsave => $_getBF(2);
  @$pb.TagNumber(3)
  set unsave($core.bool v) { $_setBool(2, v); }

  @$pb.TagNumber(4)
  $core.String get extra => $_getSZ(3);
  @$pb.TagNumber(4)
  set extra($core.String v) { $_setString(3, v); }
}

class EngineGifInfo extends $pb.GeneratedMessage {
  factory EngineGifInfo({
    $core.String? thumbB64,
    $core.int? width,
    $core.int? height,
    $core.String? mimeType,
    $core.String? fileId,
  }) {
    final $result = create();
    if (thumbB64 != null) $result.thumbB64 = thumbB64;
    if (width != null) $result.width = width;
    if (height != null) $result.height = height;
    if (mimeType != null) $result.mimeType = mimeType;
    if (fileId != null) $result.fileId = fileId;
    return $result;
  }
  EngineGifInfo._() : super();
  factory EngineGifInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGifInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGifInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'thumbB64')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'width', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'height', $pb.PbFieldType.O3)
    ..aOS(4, _omitFieldNames ? '' : 'mimeType')
    ..aOS(5, _omitFieldNames ? '' : 'fileId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGifInfo clone() => EngineGifInfo()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineGifInfo copyWith(void Function(EngineGifInfo) updates) => super.copyWith((message) => updates(message as EngineGifInfo)) as EngineGifInfo;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGifInfo create() => EngineGifInfo._();
  EngineGifInfo createEmptyInstance() => create();
  static $pb.PbList<EngineGifInfo> createRepeated() => $pb.PbList<EngineGifInfo>();
  @$core.pragma('dart2js:noInline')
  static EngineGifInfo getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGifInfo>(create);
  static EngineGifInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get thumbB64 => $_getSZ(0);
  @$pb.TagNumber(1)
  set thumbB64($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.int get width => $_getIZ(1);
  @$pb.TagNumber(2)
  set width($core.int v) { $_setSignedInt32(1, v); }

  @$pb.TagNumber(3)
  $core.int get height => $_getIZ(2);
  @$pb.TagNumber(3)
  set height($core.int v) { $_setSignedInt32(2, v); }

  @$pb.TagNumber(4)
  $core.String get mimeType => $_getSZ(3);
  @$pb.TagNumber(4)
  set mimeType($core.String v) { $_setString(3, v); }

  @$pb.TagNumber(5)
  $core.String get fileId => $_getSZ(4);
  @$pb.TagNumber(5)
  set fileId($core.String v) { $_setString(4, v); }
}

class EngineGetSavedGifsRequest extends $pb.GeneratedMessage {
  factory EngineGetSavedGifsRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    return $result;
  }
  EngineGetSavedGifsRequest._() : super();
  factory EngineGetSavedGifsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSavedGifsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetSavedGifsRequest clone() => EngineGetSavedGifsRequest()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineGetSavedGifsRequest copyWith(void Function(EngineGetSavedGifsRequest) updates) => super.copyWith((message) => updates(message as EngineGetSavedGifsRequest)) as EngineGetSavedGifsRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSavedGifsRequest create() => EngineGetSavedGifsRequest._();
  EngineGetSavedGifsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetSavedGifsRequest> createRepeated() => $pb.PbList<EngineGetSavedGifsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSavedGifsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSavedGifsRequest>(create);
  static EngineGetSavedGifsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
}

class EngineGetSavedGifsResponse extends $pb.GeneratedMessage {
  factory EngineGetSavedGifsResponse({
    $core.Iterable<EngineGifInfo>? gifs,
  }) {
    final $result = create();
    if (gifs != null) $result.gifs.addAll(gifs);
    return $result;
  }
  EngineGetSavedGifsResponse._() : super();
  factory EngineGetSavedGifsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSavedGifsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineGifInfo>(1, _omitFieldNames ? '' : 'gifs', $pb.PbFieldType.PM, subBuilder: EngineGifInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetSavedGifsResponse clone() => EngineGetSavedGifsResponse()..mergeFromMessage(this);
  @$core.Deprecated('Will be removed in next major version')
  EngineGetSavedGifsResponse copyWith(void Function(EngineGetSavedGifsResponse) updates) => super.copyWith((message) => updates(message as EngineGetSavedGifsResponse)) as EngineGetSavedGifsResponse;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSavedGifsResponse create() => EngineGetSavedGifsResponse._();
  EngineGetSavedGifsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetSavedGifsResponse> createRepeated() => $pb.PbList<EngineGetSavedGifsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSavedGifsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSavedGifsResponse>(create);
  static EngineGetSavedGifsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineGifInfo> get gifs => $_getList(0);
}

class EngineTranslateTextRequest extends $pb.GeneratedMessage {
  factory EngineTranslateTextRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.String? toLang,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (msgId != null) $result.msgId = msgId;
    if (toLang != null) $result.toLang = toLang;
    return $result;
  }
  EngineTranslateTextRequest._() : super();
  factory EngineTranslateTextRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineTranslateTextRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..aOS(4, _omitFieldNames ? '' : 'toLang')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineTranslateTextRequest clone() => EngineTranslateTextRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineTranslateTextRequest copyWith(void Function(EngineTranslateTextRequest) updates) => super.copyWith((message) => updates(message as EngineTranslateTextRequest)) as EngineTranslateTextRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineTranslateTextRequest create() => EngineTranslateTextRequest._();
  EngineTranslateTextRequest createEmptyInstance() => create();
  static $pb.PbList<EngineTranslateTextRequest> createRepeated() => $pb.PbList<EngineTranslateTextRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineTranslateTextRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineTranslateTextRequest>(create);
  static EngineTranslateTextRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }

  @$pb.TagNumber(4)
  $core.String get toLang => $_getSZ(3);
  @$pb.TagNumber(4)
  set toLang($core.String v) { $_setString(3, v); }
}

class EngineTranslateTextResponse extends $pb.GeneratedMessage {
  factory EngineTranslateTextResponse({
    $core.String? translatedText,
  }) {
    final $result = create();
    if (translatedText != null) $result.translatedText = translatedText;
    return $result;
  }
  EngineTranslateTextResponse._() : super();
  factory EngineTranslateTextResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineTranslateTextResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'translatedText')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineTranslateTextResponse clone() => EngineTranslateTextResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineTranslateTextResponse copyWith(void Function(EngineTranslateTextResponse) updates) => super.copyWith((message) => updates(message as EngineTranslateTextResponse)) as EngineTranslateTextResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineTranslateTextResponse create() => EngineTranslateTextResponse._();
  EngineTranslateTextResponse createEmptyInstance() => create();
  static $pb.PbList<EngineTranslateTextResponse> createRepeated() => $pb.PbList<EngineTranslateTextResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineTranslateTextResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineTranslateTextResponse>(create);
  static EngineTranslateTextResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get translatedText => $_getSZ(0);
  @$pb.TagNumber(1)
  set translatedText($core.String v) { $_setString(0, v); }
}

class ReportOption extends $pb.GeneratedMessage {
  factory ReportOption({
    $core.String? text,
    $core.List<$core.int>? option,
  }) {
    final $result = create();
    if (text != null) $result.text = text;
    if (option != null) $result.option = option;
    return $result;
  }
  ReportOption._() : super();
  factory ReportOption.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ReportOption', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..a<$core.List<$core.int>>(2, _omitFieldNames ? '' : 'option', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  ReportOption clone() => ReportOption()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  ReportOption copyWith(void Function(ReportOption) updates) => super.copyWith((message) => updates(message as ReportOption)) as ReportOption;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ReportOption create() => ReportOption._();
  ReportOption createEmptyInstance() => create();
  static $pb.PbList<ReportOption> createRepeated() => $pb.PbList<ReportOption>();
  @$core.pragma('dart2js:noInline')
  static ReportOption getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ReportOption>(create);
  static ReportOption? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.List<$core.int> get option => $_getN(1);
  @$pb.TagNumber(2)
  set option($core.List<$core.int> v) { $_setBytes(1, v); }
}

class EngineReportMessageRequest extends $pb.GeneratedMessage {
  factory EngineReportMessageRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.Iterable<$core.int>? msgIds,
    $core.List<$core.int>? option,
    $core.String? message,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (msgIds != null) $result.msgIds.addAll(msgIds);
    if (option != null) $result.option = option;
    if (message != null) $result.message = message;
    return $result;
  }
  EngineReportMessageRequest._() : super();
  factory EngineReportMessageRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineReportMessageRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..p<$core.int>(3, _omitFieldNames ? '' : 'msgIds', $pb.PbFieldType.K3)
    ..a<$core.List<$core.int>>(4, _omitFieldNames ? '' : 'option', $pb.PbFieldType.OY)
    ..aOS(5, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineReportMessageRequest clone() => EngineReportMessageRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineReportMessageRequest copyWith(void Function(EngineReportMessageRequest) updates) => super.copyWith((message) => updates(message as EngineReportMessageRequest)) as EngineReportMessageRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineReportMessageRequest create() => EngineReportMessageRequest._();
  EngineReportMessageRequest createEmptyInstance() => create();
  static $pb.PbList<EngineReportMessageRequest> createRepeated() => $pb.PbList<EngineReportMessageRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineReportMessageRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineReportMessageRequest>(create);
  static EngineReportMessageRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.List<$core.int> get msgIds => $_getList(2);

  @$pb.TagNumber(4)
  $core.List<$core.int> get option => $_getN(3);
  @$pb.TagNumber(4)
  set option($core.List<$core.int> v) { $_setBytes(3, v); }

  @$pb.TagNumber(5)
  $core.String get message => $_getSZ(4);
  @$pb.TagNumber(5)
  set message($core.String v) { $_setString(4, v); }
}

class EngineReportMessageResponse extends $pb.GeneratedMessage {
  factory EngineReportMessageResponse({
    $core.String? resultType,
    $core.String? title,
    $core.Iterable<ReportOption>? options,
    $core.bool? commentOptional,
    $core.List<$core.int>? commentOption,
  }) {
    final $result = create();
    if (resultType != null) $result.resultType = resultType;
    if (title != null) $result.title = title;
    if (options != null) $result.options.addAll(options);
    if (commentOptional != null) $result.commentOptional = commentOptional;
    if (commentOption != null) $result.commentOption = commentOption;
    return $result;
  }
  EngineReportMessageResponse._() : super();
  factory EngineReportMessageResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineReportMessageResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'resultType')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..pc<ReportOption>(3, _omitFieldNames ? '' : 'options', $pb.PbFieldType.PM, subBuilder: ReportOption.create)
    ..aOB(4, _omitFieldNames ? '' : 'commentOptional')
    ..a<$core.List<$core.int>>(5, _omitFieldNames ? '' : 'commentOption', $pb.PbFieldType.OY)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineReportMessageResponse clone() => EngineReportMessageResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineReportMessageResponse copyWith(void Function(EngineReportMessageResponse) updates) => super.copyWith((message) => updates(message as EngineReportMessageResponse)) as EngineReportMessageResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineReportMessageResponse create() => EngineReportMessageResponse._();
  EngineReportMessageResponse createEmptyInstance() => create();
  static $pb.PbList<EngineReportMessageResponse> createRepeated() => $pb.PbList<EngineReportMessageResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineReportMessageResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineReportMessageResponse>(create);
  static EngineReportMessageResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get resultType => $_getSZ(0);
  @$pb.TagNumber(1)
  set resultType($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.List<ReportOption> get options => $_getList(2);

  @$pb.TagNumber(4)
  $core.bool get commentOptional => $_getBF(3);
  @$pb.TagNumber(4)
  set commentOptional($core.bool v) { $_setBool(3, v); }

  @$pb.TagNumber(5)
  $core.List<$core.int> get commentOption => $_getN(4);
  @$pb.TagNumber(5)
  set commentOption($core.List<$core.int> v) { $_setBytes(4, v); }
}

class EngineVotePollRequest extends $pb.GeneratedMessage {
  factory EngineVotePollRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
    $core.int? optionIndex,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (msgId != null) $result.msgId = msgId;
    if (optionIndex != null) $result.optionIndex = optionIndex;
    return $result;
  }
  EngineVotePollRequest._() : super();
  factory EngineVotePollRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineVotePollRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'optionIndex', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineVotePollRequest clone() => EngineVotePollRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineVotePollRequest copyWith(void Function(EngineVotePollRequest) updates) => super.copyWith((message) => updates(message as EngineVotePollRequest)) as EngineVotePollRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineVotePollRequest create() => EngineVotePollRequest._();
  EngineVotePollRequest createEmptyInstance() => create();
  static $pb.PbList<EngineVotePollRequest> createRepeated() => $pb.PbList<EngineVotePollRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineVotePollRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineVotePollRequest>(create);
  static EngineVotePollRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }

  @$pb.TagNumber(4)
  $core.int get optionIndex => $_getIZ(3);
  @$pb.TagNumber(4)
  set optionIndex($core.int v) { $_setSignedInt32(3, v); }
}

class EngineRetractPollVoteRequest extends $pb.GeneratedMessage {
  factory EngineRetractPollVoteRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (msgId != null) $result.msgId = msgId;
    return $result;
  }
  EngineRetractPollVoteRequest._() : super();
  factory EngineRetractPollVoteRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineRetractPollVoteRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineRetractPollVoteRequest clone() => EngineRetractPollVoteRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineRetractPollVoteRequest copyWith(void Function(EngineRetractPollVoteRequest) updates) => super.copyWith((message) => updates(message as EngineRetractPollVoteRequest)) as EngineRetractPollVoteRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineRetractPollVoteRequest create() => EngineRetractPollVoteRequest._();
  EngineRetractPollVoteRequest createEmptyInstance() => create();
  static $pb.PbList<EngineRetractPollVoteRequest> createRepeated() => $pb.PbList<EngineRetractPollVoteRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineRetractPollVoteRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineRetractPollVoteRequest>(create);
  static EngineRetractPollVoteRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
}

class EngineStopPollRequest extends $pb.GeneratedMessage {
  factory EngineStopPollRequest({
    $core.String? accountId,
    $core.String? chatId,
    $core.String? msgId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (chatId != null) $result.chatId = chatId;
    if (msgId != null) $result.msgId = msgId;
    return $result;
  }
  EngineStopPollRequest._() : super();
  factory EngineStopPollRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineStopPollRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOS(3, _omitFieldNames ? '' : 'msgId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineStopPollRequest clone() => EngineStopPollRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineStopPollRequest copyWith(void Function(EngineStopPollRequest) updates) => super.copyWith((message) => updates(message as EngineStopPollRequest)) as EngineStopPollRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineStopPollRequest create() => EngineStopPollRequest._();
  EngineStopPollRequest createEmptyInstance() => create();
  static $pb.PbList<EngineStopPollRequest> createRepeated() => $pb.PbList<EngineStopPollRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineStopPollRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineStopPollRequest>(create);
  static EngineStopPollRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get chatId => $_getSZ(1);
  @$pb.TagNumber(2)
  set chatId($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.String get msgId => $_getSZ(2);
  @$pb.TagNumber(3)
  set msgId($core.String v) { $_setString(2, v); }
}

// ── Installed Custom Emoji Sets ──

class EngineGetInstalledEmojiSetsRequest extends $pb.GeneratedMessage {
  factory EngineGetInstalledEmojiSetsRequest({$core.String? accountId}) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    return $result;
  }
  EngineGetInstalledEmojiSetsRequest._() : super();
  factory EngineGetInstalledEmojiSetsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetInstalledEmojiSetsRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetInstalledEmojiSetsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetInstalledEmojiSetsRequest clone() => EngineGetInstalledEmojiSetsRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetInstalledEmojiSetsRequest copyWith(void Function(EngineGetInstalledEmojiSetsRequest) updates) => super.copyWith((message) => updates(message as EngineGetInstalledEmojiSetsRequest)) as EngineGetInstalledEmojiSetsRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetInstalledEmojiSetsRequest create() => EngineGetInstalledEmojiSetsRequest._();
  EngineGetInstalledEmojiSetsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetInstalledEmojiSetsRequest> createRepeated() => $pb.PbList<EngineGetInstalledEmojiSetsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetInstalledEmojiSetsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetInstalledEmojiSetsRequest>(create);
  static EngineGetInstalledEmojiSetsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
}

class EngineEmojiSetSummary extends $pb.GeneratedMessage {
  factory EngineEmojiSetSummary({
    $fixnum.Int64? setId,
    $fixnum.Int64? accessHash,
    $core.String? title,
    $core.String? shortName,
    $core.int? count,
    $core.bool? installed,
    $core.bool? premium,
    $core.Iterable<EngineStickerInfo>? stickers,
  }) {
    final $result = create();
    if (setId != null) $result.setId = setId;
    if (accessHash != null) $result.accessHash = accessHash;
    if (title != null) $result.title = title;
    if (shortName != null) $result.shortName = shortName;
    if (count != null) $result.count = count;
    if (installed != null) $result.installed = installed;
    if (premium != null) $result.premium = premium;
    if (stickers != null) $result.stickers.addAll(stickers);
    return $result;
  }
  EngineEmojiSetSummary._() : super();
  factory EngineEmojiSetSummary.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineEmojiSetSummary.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineEmojiSetSummary', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'setId')
    ..aInt64(2, _omitFieldNames ? '' : 'accessHash')
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..aOS(4, _omitFieldNames ? '' : 'shortName')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'count', $pb.PbFieldType.O3)
    ..aOB(6, _omitFieldNames ? '' : 'installed')
    ..aOB(7, _omitFieldNames ? '' : 'premium')
    ..pc<EngineStickerInfo>(8, _omitFieldNames ? '' : 'stickers', $pb.PbFieldType.PM, subBuilder: EngineStickerInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineEmojiSetSummary clone() => EngineEmojiSetSummary()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineEmojiSetSummary copyWith(void Function(EngineEmojiSetSummary) updates) => super.copyWith((message) => updates(message as EngineEmojiSetSummary)) as EngineEmojiSetSummary;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineEmojiSetSummary create() => EngineEmojiSetSummary._();
  EngineEmojiSetSummary createEmptyInstance() => create();
  static $pb.PbList<EngineEmojiSetSummary> createRepeated() => $pb.PbList<EngineEmojiSetSummary>();
  @$core.pragma('dart2js:noInline')
  static EngineEmojiSetSummary getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineEmojiSetSummary>(create);
  static EngineEmojiSetSummary? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get setId => $_getI64(0);
  @$pb.TagNumber(1)
  set setId($fixnum.Int64 v) { $_setInt64(0, v); }

  @$pb.TagNumber(2)
  $fixnum.Int64 get accessHash => $_getI64(1);
  @$pb.TagNumber(2)
  set accessHash($fixnum.Int64 v) { $_setInt64(1, v); }

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String v) { $_setString(2, v); }

  @$pb.TagNumber(4)
  $core.String get shortName => $_getSZ(3);
  @$pb.TagNumber(4)
  set shortName($core.String v) { $_setString(3, v); }

  @$pb.TagNumber(5)
  $core.int get count => $_getIZ(4);
  @$pb.TagNumber(5)
  set count($core.int v) { $_setSignedInt32(4, v); }

  @$pb.TagNumber(6)
  $core.bool get installed => $_getBF(5);
  @$pb.TagNumber(6)
  set installed($core.bool v) { $_setBool(5, v); }

  @$pb.TagNumber(7)
  $core.bool get premium => $_getBF(6);
  @$pb.TagNumber(7)
  set premium($core.bool v) { $_setBool(6, v); }

  @$pb.TagNumber(8)
  $core.List<EngineStickerInfo> get stickers => $_getList(7);
}

class EngineGetInstalledEmojiSetsResponse extends $pb.GeneratedMessage {
  factory EngineGetInstalledEmojiSetsResponse({
    $core.Iterable<EngineEmojiSetSummary>? sets,
  }) {
    final $result = create();
    if (sets != null) $result.sets.addAll(sets);
    return $result;
  }
  EngineGetInstalledEmojiSetsResponse._() : super();
  factory EngineGetInstalledEmojiSetsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetInstalledEmojiSetsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetInstalledEmojiSetsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineEmojiSetSummary>(1, _omitFieldNames ? '' : 'sets', $pb.PbFieldType.PM, subBuilder: EngineEmojiSetSummary.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetInstalledEmojiSetsResponse clone() => EngineGetInstalledEmojiSetsResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetInstalledEmojiSetsResponse copyWith(void Function(EngineGetInstalledEmojiSetsResponse) updates) => super.copyWith((message) => updates(message as EngineGetInstalledEmojiSetsResponse)) as EngineGetInstalledEmojiSetsResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetInstalledEmojiSetsResponse create() => EngineGetInstalledEmojiSetsResponse._();
  EngineGetInstalledEmojiSetsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetInstalledEmojiSetsResponse> createRepeated() => $pb.PbList<EngineGetInstalledEmojiSetsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetInstalledEmojiSetsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetInstalledEmojiSetsResponse>(create);
  static EngineGetInstalledEmojiSetsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineEmojiSetSummary> get sets => $_getList(0);
}

class EngineGetInstalledStickerPacksRequest extends $pb.GeneratedMessage {
  factory EngineGetInstalledStickerPacksRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    return $result;
  }
  EngineGetInstalledStickerPacksRequest._() : super();
  factory EngineGetInstalledStickerPacksRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetInstalledStickerPacksRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetInstalledStickerPacksRequest clone() => EngineGetInstalledStickerPacksRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetInstalledStickerPacksRequest copyWith(void Function(EngineGetInstalledStickerPacksRequest) updates) => super.copyWith((message) => updates(message as EngineGetInstalledStickerPacksRequest)) as EngineGetInstalledStickerPacksRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetInstalledStickerPacksRequest create() => EngineGetInstalledStickerPacksRequest._();
  EngineGetInstalledStickerPacksRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetInstalledStickerPacksRequest> createRepeated() => $pb.PbList<EngineGetInstalledStickerPacksRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetInstalledStickerPacksRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetInstalledStickerPacksRequest>(create);
  static EngineGetInstalledStickerPacksRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
}

class EngineStickerPackSummary extends $pb.GeneratedMessage {
  factory EngineStickerPackSummary({
    $fixnum.Int64? setId,
    $fixnum.Int64? accessHash,
    $core.String? title,
    $core.String? shortName,
    $core.int? count,
    $core.bool? animated,
    $core.bool? video,
    $core.String? thumbB64,
    $core.Iterable<EngineStickerInfo>? stickers,
    $core.bool? installed,
  }) {
    final $result = create();
    if (setId != null) $result.setId = setId;
    if (accessHash != null) $result.accessHash = accessHash;
    if (title != null) $result.title = title;
    if (shortName != null) $result.shortName = shortName;
    if (count != null) $result.count = count;
    if (animated != null) $result.animated = animated;
    if (video != null) $result.video = video;
    if (thumbB64 != null) $result.thumbB64 = thumbB64;
    if (stickers != null) $result.stickers.addAll(stickers);
    if (installed != null) $result.installed = installed;
    return $result;
  }
  EngineStickerPackSummary._() : super();
  factory EngineStickerPackSummary.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineStickerPackSummary', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'setId')
    ..aInt64(2, _omitFieldNames ? '' : 'accessHash')
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..aOS(4, _omitFieldNames ? '' : 'shortName')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'count', $pb.PbFieldType.O3)
    ..aOB(6, _omitFieldNames ? '' : 'animated')
    ..aOB(7, _omitFieldNames ? '' : 'video')
    ..aOS(8, _omitFieldNames ? '' : 'thumbB64')
    ..pc<EngineStickerInfo>(9, _omitFieldNames ? '' : 'stickers', $pb.PbFieldType.PM, subBuilder: EngineStickerInfo.create)
    ..aOB(10, _omitFieldNames ? '' : 'installed')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineStickerPackSummary clone() => EngineStickerPackSummary()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineStickerPackSummary copyWith(void Function(EngineStickerPackSummary) updates) => super.copyWith((message) => updates(message as EngineStickerPackSummary)) as EngineStickerPackSummary;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineStickerPackSummary create() => EngineStickerPackSummary._();
  EngineStickerPackSummary createEmptyInstance() => create();
  static $pb.PbList<EngineStickerPackSummary> createRepeated() => $pb.PbList<EngineStickerPackSummary>();
  @$core.pragma('dart2js:noInline')
  static EngineStickerPackSummary getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineStickerPackSummary>(create);
  static EngineStickerPackSummary? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get setId => $_getI64(0);
  @$pb.TagNumber(1)
  set setId($fixnum.Int64 v) { $_setInt64(0, v); }

  @$pb.TagNumber(2)
  $fixnum.Int64 get accessHash => $_getI64(1);
  @$pb.TagNumber(2)
  set accessHash($fixnum.Int64 v) { $_setInt64(1, v); }

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String v) { $_setString(2, v); }

  @$pb.TagNumber(4)
  $core.String get shortName => $_getSZ(3);
  @$pb.TagNumber(4)
  set shortName($core.String v) { $_setString(3, v); }

  @$pb.TagNumber(5)
  $core.int get count => $_getIZ(4);
  @$pb.TagNumber(5)
  set count($core.int v) { $_setSignedInt32(4, v); }

  @$pb.TagNumber(6)
  $core.bool get animated => $_getBF(5);
  @$pb.TagNumber(6)
  set animated($core.bool v) { $_setBool(5, v); }

  @$pb.TagNumber(7)
  $core.bool get video => $_getBF(6);
  @$pb.TagNumber(7)
  set video($core.bool v) { $_setBool(6, v); }

  @$pb.TagNumber(8)
  $core.String get thumbB64 => $_getSZ(7);
  @$pb.TagNumber(8)
  set thumbB64($core.String v) { $_setString(7, v); }

  @$pb.TagNumber(9)
  $core.List<EngineStickerInfo> get stickers => $_getList(8);

  @$pb.TagNumber(10)
  $core.bool get installed => $_getBF(9);
  @$pb.TagNumber(10)
  set installed($core.bool v) { $_setBool(9, v); }
}

class EngineGetInstalledStickerPacksResponse extends $pb.GeneratedMessage {
  factory EngineGetInstalledStickerPacksResponse({
    $core.Iterable<EngineStickerPackSummary>? packs,
  }) {
    final $result = create();
    if (packs != null) $result.packs.addAll(packs);
    return $result;
  }
  EngineGetInstalledStickerPacksResponse._() : super();
  factory EngineGetInstalledStickerPacksResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetInstalledStickerPacksResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineStickerPackSummary>(1, _omitFieldNames ? '' : 'packs', $pb.PbFieldType.PM, subBuilder: EngineStickerPackSummary.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetInstalledStickerPacksResponse clone() => EngineGetInstalledStickerPacksResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetInstalledStickerPacksResponse copyWith(void Function(EngineGetInstalledStickerPacksResponse) updates) => super.copyWith((message) => updates(message as EngineGetInstalledStickerPacksResponse)) as EngineGetInstalledStickerPacksResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetInstalledStickerPacksResponse create() => EngineGetInstalledStickerPacksResponse._();
  EngineGetInstalledStickerPacksResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetInstalledStickerPacksResponse> createRepeated() => $pb.PbList<EngineGetInstalledStickerPacksResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetInstalledStickerPacksResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetInstalledStickerPacksResponse>(create);
  static EngineGetInstalledStickerPacksResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineStickerPackSummary> get packs => $_getList(0);
}

class EngineGetRecentStickersRequest extends $pb.GeneratedMessage {
  factory EngineGetRecentStickersRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    return $result;
  }
  EngineGetRecentStickersRequest._() : super();
  factory EngineGetRecentStickersRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetRecentStickersRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetRecentStickersRequest clone() => EngineGetRecentStickersRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetRecentStickersRequest copyWith(void Function(EngineGetRecentStickersRequest) updates) => super.copyWith((message) => updates(message as EngineGetRecentStickersRequest)) as EngineGetRecentStickersRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetRecentStickersRequest create() => EngineGetRecentStickersRequest._();
  EngineGetRecentStickersRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetRecentStickersRequest> createRepeated() => $pb.PbList<EngineGetRecentStickersRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetRecentStickersRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetRecentStickersRequest>(create);
  static EngineGetRecentStickersRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
}

class EngineGetRecentStickersResponse extends $pb.GeneratedMessage {
  factory EngineGetRecentStickersResponse({
    $core.Iterable<EngineStickerInfo>? stickers,
  }) {
    final $result = create();
    if (stickers != null) $result.stickers.addAll(stickers);
    return $result;
  }
  EngineGetRecentStickersResponse._() : super();
  factory EngineGetRecentStickersResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetRecentStickersResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineStickerInfo>(1, _omitFieldNames ? '' : 'stickers', $pb.PbFieldType.PM, subBuilder: EngineStickerInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetRecentStickersResponse clone() => EngineGetRecentStickersResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetRecentStickersResponse copyWith(void Function(EngineGetRecentStickersResponse) updates) => super.copyWith((message) => updates(message as EngineGetRecentStickersResponse)) as EngineGetRecentStickersResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetRecentStickersResponse create() => EngineGetRecentStickersResponse._();
  EngineGetRecentStickersResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetRecentStickersResponse> createRepeated() => $pb.PbList<EngineGetRecentStickersResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetRecentStickersResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetRecentStickersResponse>(create);
  static EngineGetRecentStickersResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineStickerInfo> get stickers => $_getList(0);
}

class EngineGetFeaturedStickerPacksRequest extends $pb.GeneratedMessage {
  factory EngineGetFeaturedStickerPacksRequest({
    $core.String? accountId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    return $result;
  }
  EngineGetFeaturedStickerPacksRequest._() : super();
  factory EngineGetFeaturedStickerPacksRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetFeaturedStickerPacksRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetFeaturedStickerPacksRequest clone() => EngineGetFeaturedStickerPacksRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetFeaturedStickerPacksRequest copyWith(void Function(EngineGetFeaturedStickerPacksRequest) updates) => super.copyWith((message) => updates(message as EngineGetFeaturedStickerPacksRequest)) as EngineGetFeaturedStickerPacksRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetFeaturedStickerPacksRequest create() => EngineGetFeaturedStickerPacksRequest._();
  EngineGetFeaturedStickerPacksRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetFeaturedStickerPacksRequest> createRepeated() => $pb.PbList<EngineGetFeaturedStickerPacksRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetFeaturedStickerPacksRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetFeaturedStickerPacksRequest>(create);
  static EngineGetFeaturedStickerPacksRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
}

class EngineGetFeaturedStickerPacksResponse extends $pb.GeneratedMessage {
  factory EngineGetFeaturedStickerPacksResponse({
    $core.Iterable<EngineStickerPackSummary>? packs,
  }) {
    final $result = create();
    if (packs != null) $result.packs.addAll(packs);
    return $result;
  }
  EngineGetFeaturedStickerPacksResponse._() : super();
  factory EngineGetFeaturedStickerPacksResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetFeaturedStickerPacksResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineStickerPackSummary>(1, _omitFieldNames ? '' : 'packs', $pb.PbFieldType.PM, subBuilder: EngineStickerPackSummary.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetFeaturedStickerPacksResponse clone() => EngineGetFeaturedStickerPacksResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetFeaturedStickerPacksResponse copyWith(void Function(EngineGetFeaturedStickerPacksResponse) updates) => super.copyWith((message) => updates(message as EngineGetFeaturedStickerPacksResponse)) as EngineGetFeaturedStickerPacksResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetFeaturedStickerPacksResponse create() => EngineGetFeaturedStickerPacksResponse._();
  EngineGetFeaturedStickerPacksResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetFeaturedStickerPacksResponse> createRepeated() => $pb.PbList<EngineGetFeaturedStickerPacksResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetFeaturedStickerPacksResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetFeaturedStickerPacksResponse>(create);
  static EngineGetFeaturedStickerPacksResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineStickerPackSummary> get packs => $_getList(0);
}

class EngineSearchStickerSetsRequest extends $pb.GeneratedMessage {
  factory EngineSearchStickerSetsRequest({
    $core.String? accountId,
    $core.String? query,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (query != null) $result.query = query;
    return $result;
  }
  EngineSearchStickerSetsRequest._() : super();
  factory EngineSearchStickerSetsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSearchStickerSetsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'query')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineSearchStickerSetsRequest clone() => EngineSearchStickerSetsRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineSearchStickerSetsRequest copyWith(void Function(EngineSearchStickerSetsRequest) updates) => super.copyWith((message) => updates(message as EngineSearchStickerSetsRequest)) as EngineSearchStickerSetsRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineSearchStickerSetsRequest create() => EngineSearchStickerSetsRequest._();
  EngineSearchStickerSetsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSearchStickerSetsRequest> createRepeated() => $pb.PbList<EngineSearchStickerSetsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSearchStickerSetsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSearchStickerSetsRequest>(create);
  static EngineSearchStickerSetsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get query => $_getSZ(1);
  @$pb.TagNumber(2)
  set query($core.String v) { $_setString(1, v); }
}

class EngineSearchStickerSetsResponse extends $pb.GeneratedMessage {
  factory EngineSearchStickerSetsResponse({
    $core.Iterable<EngineStickerPackSummary>? packs,
  }) {
    final $result = create();
    if (packs != null) $result.packs.addAll(packs);
    return $result;
  }
  EngineSearchStickerSetsResponse._() : super();
  factory EngineSearchStickerSetsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSearchStickerSetsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineStickerPackSummary>(1, _omitFieldNames ? '' : 'packs', $pb.PbFieldType.PM, subBuilder: EngineStickerPackSummary.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineSearchStickerSetsResponse clone() => EngineSearchStickerSetsResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineSearchStickerSetsResponse copyWith(void Function(EngineSearchStickerSetsResponse) updates) => super.copyWith((message) => updates(message as EngineSearchStickerSetsResponse)) as EngineSearchStickerSetsResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineSearchStickerSetsResponse create() => EngineSearchStickerSetsResponse._();
  EngineSearchStickerSetsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineSearchStickerSetsResponse> createRepeated() => $pb.PbList<EngineSearchStickerSetsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineSearchStickerSetsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSearchStickerSetsResponse>(create);
  static EngineSearchStickerSetsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineStickerPackSummary> get packs => $_getList(0);
}

class EngineInstallStickerSetRequest extends $pb.GeneratedMessage {
  factory EngineInstallStickerSetRequest({
    $core.String? accountId,
    $fixnum.Int64? setId,
    $fixnum.Int64? accessHash,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (setId != null) $result.setId = setId;
    if (accessHash != null) $result.accessHash = accessHash;
    return $result;
  }
  EngineInstallStickerSetRequest._() : super();
  factory EngineInstallStickerSetRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineInstallStickerSetRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aInt64(2, _omitFieldNames ? '' : 'setId')
    ..aInt64(3, _omitFieldNames ? '' : 'accessHash')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineInstallStickerSetRequest clone() => EngineInstallStickerSetRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineInstallStickerSetRequest copyWith(void Function(EngineInstallStickerSetRequest) updates) => super.copyWith((message) => updates(message as EngineInstallStickerSetRequest)) as EngineInstallStickerSetRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineInstallStickerSetRequest create() => EngineInstallStickerSetRequest._();
  EngineInstallStickerSetRequest createEmptyInstance() => create();
  static $pb.PbList<EngineInstallStickerSetRequest> createRepeated() => $pb.PbList<EngineInstallStickerSetRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineInstallStickerSetRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineInstallStickerSetRequest>(create);
  static EngineInstallStickerSetRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $fixnum.Int64 get setId => $_getI64(1);
  @$pb.TagNumber(2)
  set setId($fixnum.Int64 v) { $_setInt64(1, v); }

  @$pb.TagNumber(3)
  $fixnum.Int64 get accessHash => $_getI64(2);
  @$pb.TagNumber(3)
  set accessHash($fixnum.Int64 v) { $_setInt64(2, v); }
}

class EngineInstallStickerSetResponse extends $pb.GeneratedMessage {
  factory EngineInstallStickerSetResponse() => create();
  EngineInstallStickerSetResponse._() : super();
  factory EngineInstallStickerSetResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineInstallStickerSetResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineInstallStickerSetResponse clone() => EngineInstallStickerSetResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineInstallStickerSetResponse copyWith(void Function(EngineInstallStickerSetResponse) updates) => super.copyWith((message) => updates(message as EngineInstallStickerSetResponse)) as EngineInstallStickerSetResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineInstallStickerSetResponse create() => EngineInstallStickerSetResponse._();
  EngineInstallStickerSetResponse createEmptyInstance() => create();
  static $pb.PbList<EngineInstallStickerSetResponse> createRepeated() => $pb.PbList<EngineInstallStickerSetResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineInstallStickerSetResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineInstallStickerSetResponse>(create);
  static EngineInstallStickerSetResponse? _defaultInstance;
}

class EngineGetStickerSuggestionsRequest extends $pb.GeneratedMessage {
  factory EngineGetStickerSuggestionsRequest({
    $core.String? accountId,
    $core.String? emoji,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (emoji != null) $result.emoji = emoji;
    return $result;
  }
  EngineGetStickerSuggestionsRequest._() : super();
  factory EngineGetStickerSuggestionsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetStickerSuggestionsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'emoji')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetStickerSuggestionsRequest clone() => EngineGetStickerSuggestionsRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetStickerSuggestionsRequest copyWith(void Function(EngineGetStickerSuggestionsRequest) updates) => super.copyWith((message) => updates(message as EngineGetStickerSuggestionsRequest)) as EngineGetStickerSuggestionsRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetStickerSuggestionsRequest create() => EngineGetStickerSuggestionsRequest._();
  EngineGetStickerSuggestionsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetStickerSuggestionsRequest> createRepeated() => $pb.PbList<EngineGetStickerSuggestionsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetStickerSuggestionsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetStickerSuggestionsRequest>(create);
  static EngineGetStickerSuggestionsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get emoji => $_getSZ(1);
  @$pb.TagNumber(2)
  set emoji($core.String v) { $_setString(1, v); }
}

class EngineGetStickerSuggestionsResponse extends $pb.GeneratedMessage {
  factory EngineGetStickerSuggestionsResponse({
    $core.Iterable<EngineStickerInfo>? stickers,
  }) {
    final $result = create();
    if (stickers != null) $result.stickers.addAll(stickers);
    return $result;
  }
  EngineGetStickerSuggestionsResponse._() : super();
  factory EngineGetStickerSuggestionsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetStickerSuggestionsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineStickerInfo>(1, _omitFieldNames ? '' : 'stickers', $pb.PbFieldType.PM, subBuilder: EngineStickerInfo.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineGetStickerSuggestionsResponse clone() => EngineGetStickerSuggestionsResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineGetStickerSuggestionsResponse copyWith(void Function(EngineGetStickerSuggestionsResponse) updates) => super.copyWith((message) => updates(message as EngineGetStickerSuggestionsResponse)) as EngineGetStickerSuggestionsResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetStickerSuggestionsResponse create() => EngineGetStickerSuggestionsResponse._();
  EngineGetStickerSuggestionsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetStickerSuggestionsResponse> createRepeated() => $pb.PbList<EngineGetStickerSuggestionsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetStickerSuggestionsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetStickerSuggestionsResponse>(create);
  static EngineGetStickerSuggestionsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineStickerInfo> get stickers => $_getList(0);
}

class EngineSendCallRatingRequest extends $pb.GeneratedMessage {
  factory EngineSendCallRatingRequest({
    $core.String? accountId,
    $core.String? callId,
    $core.int? rating,
    $core.String? comment,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (callId != null) $result.callId = callId;
    if (rating != null) $result.rating = rating;
    if (comment != null) $result.comment = comment;
    return $result;
  }
  EngineSendCallRatingRequest._() : super();
  factory EngineSendCallRatingRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSendCallRatingRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'callId')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'rating', $pb.PbFieldType.O3)
    ..aOS(4, _omitFieldNames ? '' : 'comment')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineSendCallRatingRequest clone() => EngineSendCallRatingRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineSendCallRatingRequest copyWith(void Function(EngineSendCallRatingRequest) updates) => super.copyWith((message) => updates(message as EngineSendCallRatingRequest)) as EngineSendCallRatingRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineSendCallRatingRequest create() => EngineSendCallRatingRequest._();
  EngineSendCallRatingRequest createEmptyInstance() => create();
  static $pb.PbList<EngineSendCallRatingRequest> createRepeated() => $pb.PbList<EngineSendCallRatingRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineSendCallRatingRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSendCallRatingRequest>(create);
  static EngineSendCallRatingRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get callId => $_getSZ(1);
  @$pb.TagNumber(2)
  set callId($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.int get rating => $_getIZ(2);
  @$pb.TagNumber(3)
  set rating($core.int v) { $_setSignedInt32(2, v); }

  @$pb.TagNumber(4)
  $core.String get comment => $_getSZ(3);
  @$pb.TagNumber(4)
  set comment($core.String v) { $_setString(3, v); }
}

class EngineFetchPeerStoriesRequest extends $pb.GeneratedMessage {
  factory EngineFetchPeerStoriesRequest({
    $core.String? accountId,
    $core.String? peerId,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (peerId != null) $result.peerId = peerId;
    return $result;
  }
  EngineFetchPeerStoriesRequest._() : super();
  factory EngineFetchPeerStoriesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineFetchPeerStoriesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'peerId')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineFetchPeerStoriesRequest clone() => EngineFetchPeerStoriesRequest()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineFetchPeerStoriesRequest copyWith(void Function(EngineFetchPeerStoriesRequest) updates) => super.copyWith((message) => updates(message as EngineFetchPeerStoriesRequest)) as EngineFetchPeerStoriesRequest;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineFetchPeerStoriesRequest create() => EngineFetchPeerStoriesRequest._();
  EngineFetchPeerStoriesRequest createEmptyInstance() => create();
  static $pb.PbList<EngineFetchPeerStoriesRequest> createRepeated() => $pb.PbList<EngineFetchPeerStoriesRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineFetchPeerStoriesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineFetchPeerStoriesRequest>(create);
  static EngineFetchPeerStoriesRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get peerId => $_getSZ(1);
  @$pb.TagNumber(2)
  set peerId($core.String v) { $_setString(1, v); }
}

class EngineFetchPeerStoriesResponse extends $pb.GeneratedMessage {
  factory EngineFetchPeerStoriesResponse({
    $core.String? storiesJson,
  }) {
    final $result = create();
    if (storiesJson != null) $result.storiesJson = storiesJson;
    return $result;
  }
  EngineFetchPeerStoriesResponse._() : super();
  factory EngineFetchPeerStoriesResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineFetchPeerStoriesResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'storiesJson')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Use deepCopy instead')
  EngineFetchPeerStoriesResponse clone() => EngineFetchPeerStoriesResponse()..mergeFromMessage(this);
  @$core.Deprecated('Use rebuild instead')
  EngineFetchPeerStoriesResponse copyWith(void Function(EngineFetchPeerStoriesResponse) updates) => super.copyWith((message) => updates(message as EngineFetchPeerStoriesResponse)) as EngineFetchPeerStoriesResponse;
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineFetchPeerStoriesResponse create() => EngineFetchPeerStoriesResponse._();
  EngineFetchPeerStoriesResponse createEmptyInstance() => create();
  static $pb.PbList<EngineFetchPeerStoriesResponse> createRepeated() => $pb.PbList<EngineFetchPeerStoriesResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineFetchPeerStoriesResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineFetchPeerStoriesResponse>(create);
  static EngineFetchPeerStoriesResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get storiesJson => $_getSZ(0);
  @$pb.TagNumber(1)
  set storiesJson($core.String v) { $_setString(0, v); }
}

// ── Story Albums ──

class EngineGetStoryAlbumsRequest extends $pb.GeneratedMessage {
  factory EngineGetStoryAlbumsRequest({$core.String? accountId}) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    return $result;
  }
  EngineGetStoryAlbumsRequest._() : super();
  factory EngineGetStoryAlbumsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetStoryAlbumsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..hasRequiredFields = false;
  @$core.Deprecated('Use deepCopy instead')
  EngineGetStoryAlbumsRequest clone() => EngineGetStoryAlbumsRequest()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetStoryAlbumsRequest create() => EngineGetStoryAlbumsRequest._();
  EngineGetStoryAlbumsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetStoryAlbumsRequest> createRepeated() => $pb.PbList<EngineGetStoryAlbumsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetStoryAlbumsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetStoryAlbumsRequest>(create);
  static EngineGetStoryAlbumsRequest? _defaultInstance;
  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
}

class EngineStoryAlbum extends $pb.GeneratedMessage {
  factory EngineStoryAlbum({$fixnum.Int64? id, $core.String? title, $core.int? count}) {
    final $result = create();
    if (id != null) $result.id = id;
    if (title != null) $result.title = title;
    if (count != null) $result.count = count;
    return $result;
  }
  EngineStoryAlbum._() : super();
  factory EngineStoryAlbum.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineStoryAlbum', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'count', $pb.PbFieldType.O3)
    ..hasRequiredFields = false;
  @$core.Deprecated('Use deepCopy instead')
  EngineStoryAlbum clone() => EngineStoryAlbum()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineStoryAlbum create() => EngineStoryAlbum._();
  EngineStoryAlbum createEmptyInstance() => create();
  static $pb.PbList<EngineStoryAlbum> createRepeated() => $pb.PbList<EngineStoryAlbum>();
  @$core.pragma('dart2js:noInline')
  static EngineStoryAlbum getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineStoryAlbum>(create);
  static EngineStoryAlbum? _defaultInstance;
  @$pb.TagNumber(1)
  $fixnum.Int64 get id => $_getI64(0);
  @$pb.TagNumber(1)
  set id($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(3)
  $core.int get count => $_getIZ(2);
  @$pb.TagNumber(3)
  set count($core.int v) { $_setSignedInt32(2, v); }
}

class EngineGetStoryAlbumsResponse extends $pb.GeneratedMessage {
  factory EngineGetStoryAlbumsResponse({$core.Iterable<EngineStoryAlbum>? albums}) {
    final $result = create();
    if (albums != null) $result.albums.addAll(albums);
    return $result;
  }
  EngineGetStoryAlbumsResponse._() : super();
  factory EngineGetStoryAlbumsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetStoryAlbumsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineStoryAlbum>(1, _omitFieldNames ? '' : 'albums', $pb.PbFieldType.PM, subBuilder: EngineStoryAlbum.create)
    ..hasRequiredFields = false;
  @$core.Deprecated('Use deepCopy instead')
  EngineGetStoryAlbumsResponse clone() => EngineGetStoryAlbumsResponse()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetStoryAlbumsResponse create() => EngineGetStoryAlbumsResponse._();
  EngineGetStoryAlbumsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetStoryAlbumsResponse> createRepeated() => $pb.PbList<EngineGetStoryAlbumsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetStoryAlbumsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetStoryAlbumsResponse>(create);
  static EngineGetStoryAlbumsResponse? _defaultInstance;
  @$pb.TagNumber(1)
  $core.List<EngineStoryAlbum> get albums => $_getList(0);
}

class EngineGetAlbumStoriesRequest extends $pb.GeneratedMessage {
  factory EngineGetAlbumStoriesRequest({$core.String? accountId, $fixnum.Int64? albumId, $core.int? offset, $core.int? limit}) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (albumId != null) $result.albumId = albumId;
    if (offset != null) $result.offset = offset;
    if (limit != null) $result.limit = limit;
    return $result;
  }
  EngineGetAlbumStoriesRequest._() : super();
  factory EngineGetAlbumStoriesRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetAlbumStoriesRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aInt64(2, _omitFieldNames ? '' : 'albumId')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'offset', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.O3)
    ..hasRequiredFields = false;
  @$core.Deprecated('Use deepCopy instead')
  EngineGetAlbumStoriesRequest clone() => EngineGetAlbumStoriesRequest()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetAlbumStoriesRequest create() => EngineGetAlbumStoriesRequest._();
  EngineGetAlbumStoriesRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetAlbumStoriesRequest> createRepeated() => $pb.PbList<EngineGetAlbumStoriesRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetAlbumStoriesRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetAlbumStoriesRequest>(create);
  static EngineGetAlbumStoriesRequest? _defaultInstance;
  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(2)
  $fixnum.Int64 get albumId => $_getI64(1);
  @$pb.TagNumber(2)
  set albumId($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(3)
  $core.int get offset => $_getIZ(2);
  @$pb.TagNumber(3)
  set offset($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(4)
  $core.int get limit => $_getIZ(3);
  @$pb.TagNumber(4)
  set limit($core.int v) { $_setSignedInt32(3, v); }
}

class EngineGetAlbumStoriesResponse extends $pb.GeneratedMessage {
  factory EngineGetAlbumStoriesResponse({$core.String? storiesJson, $core.int? totalCount}) {
    final $result = create();
    if (storiesJson != null) $result.storiesJson = storiesJson;
    if (totalCount != null) $result.totalCount = totalCount;
    return $result;
  }
  EngineGetAlbumStoriesResponse._() : super();
  factory EngineGetAlbumStoriesResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetAlbumStoriesResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'storiesJson')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'totalCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false;
  @$core.Deprecated('Use deepCopy instead')
  EngineGetAlbumStoriesResponse clone() => EngineGetAlbumStoriesResponse()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetAlbumStoriesResponse create() => EngineGetAlbumStoriesResponse._();
  EngineGetAlbumStoriesResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetAlbumStoriesResponse> createRepeated() => $pb.PbList<EngineGetAlbumStoriesResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetAlbumStoriesResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetAlbumStoriesResponse>(create);
  static EngineGetAlbumStoriesResponse? _defaultInstance;
  @$pb.TagNumber(1)
  $core.String get storiesJson => $_getSZ(0);
  @$pb.TagNumber(1)
  set storiesJson($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(2)
  $core.int get totalCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set totalCount($core.int v) { $_setSignedInt32(1, v); }
}

class EngineCreateStoryAlbumRequest extends $pb.GeneratedMessage {
  factory EngineCreateStoryAlbumRequest({$core.String? accountId, $core.String? title}) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (title != null) $result.title = title;
    return $result;
  }
  EngineCreateStoryAlbumRequest._() : super();
  factory EngineCreateStoryAlbumRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCreateStoryAlbumRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..hasRequiredFields = false;
  @$core.Deprecated('Use deepCopy instead')
  EngineCreateStoryAlbumRequest clone() => EngineCreateStoryAlbumRequest()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineCreateStoryAlbumRequest create() => EngineCreateStoryAlbumRequest._();
  EngineCreateStoryAlbumRequest createEmptyInstance() => create();
  static $pb.PbList<EngineCreateStoryAlbumRequest> createRepeated() => $pb.PbList<EngineCreateStoryAlbumRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineCreateStoryAlbumRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCreateStoryAlbumRequest>(create);
  static EngineCreateStoryAlbumRequest? _defaultInstance;
  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String v) { $_setString(1, v); }
}

class EngineCreateStoryAlbumResponse extends $pb.GeneratedMessage {
  factory EngineCreateStoryAlbumResponse({$fixnum.Int64? albumId, $core.String? title}) {
    final $result = create();
    if (albumId != null) $result.albumId = albumId;
    if (title != null) $result.title = title;
    return $result;
  }
  EngineCreateStoryAlbumResponse._() : super();
  factory EngineCreateStoryAlbumResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCreateStoryAlbumResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'albumId')
    ..aOS(2, _omitFieldNames ? '' : 'title')
    ..hasRequiredFields = false;
  @$core.Deprecated('Use deepCopy instead')
  EngineCreateStoryAlbumResponse clone() => EngineCreateStoryAlbumResponse()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineCreateStoryAlbumResponse create() => EngineCreateStoryAlbumResponse._();
  EngineCreateStoryAlbumResponse createEmptyInstance() => create();
  static $pb.PbList<EngineCreateStoryAlbumResponse> createRepeated() => $pb.PbList<EngineCreateStoryAlbumResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineCreateStoryAlbumResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCreateStoryAlbumResponse>(create);
  static EngineCreateStoryAlbumResponse? _defaultInstance;
  @$pb.TagNumber(1)
  $fixnum.Int64 get albumId => $_getI64(0);
  @$pb.TagNumber(1)
  set albumId($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(2)
  $core.String get title => $_getSZ(1);
  @$pb.TagNumber(2)
  set title($core.String v) { $_setString(1, v); }
}

class EngineReorderStoryAlbumsRequest extends $pb.GeneratedMessage {
  factory EngineReorderStoryAlbumsRequest({$core.String? accountId, $core.Iterable<$fixnum.Int64>? albumIds}) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (albumIds != null) $result.albumIds.addAll(albumIds);
    return $result;
  }
  EngineReorderStoryAlbumsRequest._() : super();
  factory EngineReorderStoryAlbumsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineReorderStoryAlbumsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..p<$fixnum.Int64>(2, _omitFieldNames ? '' : 'albumIds', $pb.PbFieldType.K6)
    ..hasRequiredFields = false;
  @$core.Deprecated('Use deepCopy instead')
  EngineReorderStoryAlbumsRequest clone() => EngineReorderStoryAlbumsRequest()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineReorderStoryAlbumsRequest create() => EngineReorderStoryAlbumsRequest._();
  EngineReorderStoryAlbumsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineReorderStoryAlbumsRequest> createRepeated() => $pb.PbList<EngineReorderStoryAlbumsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineReorderStoryAlbumsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineReorderStoryAlbumsRequest>(create);
  static EngineReorderStoryAlbumsRequest? _defaultInstance;
  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(2)
  $core.List<$fixnum.Int64> get albumIds => $_getList(1);
}

class EngineGetCustomEmojiThumbsRequest extends $pb.GeneratedMessage {
  factory EngineGetCustomEmojiThumbsRequest({
    $core.String? accountId,
    $core.Iterable<$fixnum.Int64>? documentIds,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (documentIds != null) $result.documentIds.addAll(documentIds);
    return $result;
  }
  EngineGetCustomEmojiThumbsRequest._() : super();
  factory EngineGetCustomEmojiThumbsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetCustomEmojiThumbsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..p<$fixnum.Int64>(2, _omitFieldNames ? '' : 'documentIds', $pb.PbFieldType.K6)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetCustomEmojiThumbsRequest clone() => EngineGetCustomEmojiThumbsRequest()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetCustomEmojiThumbsRequest create() => EngineGetCustomEmojiThumbsRequest._();
  EngineGetCustomEmojiThumbsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetCustomEmojiThumbsRequest> createRepeated() => $pb.PbList<EngineGetCustomEmojiThumbsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetCustomEmojiThumbsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetCustomEmojiThumbsRequest>(create);
  static EngineGetCustomEmojiThumbsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.List<$fixnum.Int64> get documentIds => $_getList(1);
}

class EngineCustomEmojiThumb extends $pb.GeneratedMessage {
  factory EngineCustomEmojiThumb({
    $fixnum.Int64? documentId,
    $core.String? thumbB64,
  }) {
    final $result = create();
    if (documentId != null) $result.documentId = documentId;
    if (thumbB64 != null) $result.thumbB64 = thumbB64;
    return $result;
  }
  EngineCustomEmojiThumb._() : super();
  factory EngineCustomEmojiThumb.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineCustomEmojiThumb', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'documentId')
    ..aOS(2, _omitFieldNames ? '' : 'thumbB64')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineCustomEmojiThumb clone() => EngineCustomEmojiThumb()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineCustomEmojiThumb create() => EngineCustomEmojiThumb._();
  EngineCustomEmojiThumb createEmptyInstance() => create();
  static $pb.PbList<EngineCustomEmojiThumb> createRepeated() => $pb.PbList<EngineCustomEmojiThumb>();
  @$core.pragma('dart2js:noInline')
  static EngineCustomEmojiThumb getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineCustomEmojiThumb>(create);
  static EngineCustomEmojiThumb? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get documentId => $_getI64(0);
  @$pb.TagNumber(1)
  set documentId($fixnum.Int64 v) { $_setInt64(0, v); }

  @$pb.TagNumber(2)
  $core.String get thumbB64 => $_getSZ(1);
  @$pb.TagNumber(2)
  set thumbB64($core.String v) { $_setString(1, v); }
}

class EngineGetCustomEmojiThumbsResponse extends $pb.GeneratedMessage {
  factory EngineGetCustomEmojiThumbsResponse({
    $core.Iterable<EngineCustomEmojiThumb>? thumbs,
  }) {
    final $result = create();
    if (thumbs != null) $result.thumbs.addAll(thumbs);
    return $result;
  }
  EngineGetCustomEmojiThumbsResponse._() : super();
  factory EngineGetCustomEmojiThumbsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetCustomEmojiThumbsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineCustomEmojiThumb>(1, _omitFieldNames ? '' : 'thumbs', $pb.PbFieldType.PM, subBuilder: EngineCustomEmojiThumb.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetCustomEmojiThumbsResponse clone() => EngineGetCustomEmojiThumbsResponse()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetCustomEmojiThumbsResponse create() => EngineGetCustomEmojiThumbsResponse._();
  EngineGetCustomEmojiThumbsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetCustomEmojiThumbsResponse> createRepeated() => $pb.PbList<EngineGetCustomEmojiThumbsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetCustomEmojiThumbsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetCustomEmojiThumbsResponse>(create);
  static EngineGetCustomEmojiThumbsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineCustomEmojiThumb> get thumbs => $_getList(0);
}

class EngineGetSavedSublistsRequest extends $pb.GeneratedMessage {
  factory EngineGetSavedSublistsRequest({
    $core.String? accountId,
    $core.int? limit,
    $core.int? offsetDate,
    $core.int? offsetId,
    $core.bool? excludePinned,
  }) {
    final $result = create();
    if (accountId != null) $result.accountId = accountId;
    if (limit != null) $result.limit = limit;
    if (offsetDate != null) $result.offsetDate = offsetDate;
    if (offsetId != null) $result.offsetId = offsetId;
    if (excludePinned != null) $result.excludePinned = excludePinned;
    return $result;
  }
  EngineGetSavedSublistsRequest._() : super();
  factory EngineGetSavedSublistsRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSavedSublistsRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'limit', $pb.PbFieldType.O3)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'offsetDate', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'offsetId', $pb.PbFieldType.O3)
    ..aOB(5, _omitFieldNames ? '' : 'excludePinned')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetSavedSublistsRequest clone() => EngineGetSavedSublistsRequest()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetSavedSublistsRequest create() => EngineGetSavedSublistsRequest._();
  EngineGetSavedSublistsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetSavedSublistsRequest> createRepeated() => $pb.PbList<EngineGetSavedSublistsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSavedSublistsRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSavedSublistsRequest>(create);
  static EngineGetSavedSublistsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.int get limit => $_getIZ(1);
  @$pb.TagNumber(2)
  set limit($core.int v) { $_setSignedInt32(1, v); }

  @$pb.TagNumber(3)
  $core.int get offsetDate => $_getIZ(2);
  @$pb.TagNumber(3)
  set offsetDate($core.int v) { $_setSignedInt32(2, v); }

  @$pb.TagNumber(4)
  $core.int get offsetId => $_getIZ(3);
  @$pb.TagNumber(4)
  set offsetId($core.int v) { $_setSignedInt32(3, v); }

  @$pb.TagNumber(5)
  $core.bool get excludePinned => $_getBF(4);
  @$pb.TagNumber(5)
  set excludePinned($core.bool v) { $_setBool(4, v); }
}

class EngineSavedSublist extends $pb.GeneratedMessage {
  factory EngineSavedSublist({
    $core.String? peerId,
    $core.String? peerName,
    $core.String? avatarPath,
    $core.int? type,
    $core.bool? isPinned,
    $core.int? topMessage,
    $core.String? lastMsgText,
    $fixnum.Int64? lastMsgTime,
    $core.bool? isSelf,
    $core.int? unreadCount,
  }) {
    final $result = create();
    if (peerId != null) $result.peerId = peerId;
    if (peerName != null) $result.peerName = peerName;
    if (avatarPath != null) $result.avatarPath = avatarPath;
    if (type != null) $result.type = type;
    if (isPinned != null) $result.isPinned = isPinned;
    if (topMessage != null) $result.topMessage = topMessage;
    if (lastMsgText != null) $result.lastMsgText = lastMsgText;
    if (lastMsgTime != null) $result.lastMsgTime = lastMsgTime;
    if (isSelf != null) $result.isSelf = isSelf;
    if (unreadCount != null) $result.unreadCount = unreadCount;
    return $result;
  }
  EngineSavedSublist._() : super();
  factory EngineSavedSublist.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineSavedSublist', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'peerId')
    ..aOS(2, _omitFieldNames ? '' : 'peerName')
    ..aOS(3, _omitFieldNames ? '' : 'avatarPath')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'type', $pb.PbFieldType.O3)
    ..aOB(5, _omitFieldNames ? '' : 'isPinned')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'topMessage', $pb.PbFieldType.O3)
    ..aOS(7, _omitFieldNames ? '' : 'lastMsgText')
    ..aInt64(8, _omitFieldNames ? '' : 'lastMsgTime')
    ..aOB(9, _omitFieldNames ? '' : 'isSelf')
    ..a<$core.int>(10, _omitFieldNames ? '' : 'unreadCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineSavedSublist clone() => EngineSavedSublist()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineSavedSublist create() => EngineSavedSublist._();
  EngineSavedSublist createEmptyInstance() => create();
  static $pb.PbList<EngineSavedSublist> createRepeated() => $pb.PbList<EngineSavedSublist>();
  @$core.pragma('dart2js:noInline')
  static EngineSavedSublist getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineSavedSublist>(create);
  static EngineSavedSublist? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get peerId => $_getSZ(0);
  @$pb.TagNumber(1)
  set peerId($core.String v) { $_setString(0, v); }

  @$pb.TagNumber(2)
  $core.String get peerName => $_getSZ(1);
  @$pb.TagNumber(2)
  set peerName($core.String v) { $_setString(1, v); }

  @$pb.TagNumber(3)
  $core.String get avatarPath => $_getSZ(2);
  @$pb.TagNumber(3)
  set avatarPath($core.String v) { $_setString(2, v); }

  @$pb.TagNumber(4)
  $core.int get type => $_getIZ(3);
  @$pb.TagNumber(4)
  set type($core.int v) { $_setSignedInt32(3, v); }

  @$pb.TagNumber(5)
  $core.bool get isPinned => $_getBF(4);
  @$pb.TagNumber(5)
  set isPinned($core.bool v) { $_setBool(4, v); }

  @$pb.TagNumber(6)
  $core.int get topMessage => $_getIZ(5);
  @$pb.TagNumber(6)
  set topMessage($core.int v) { $_setSignedInt32(5, v); }

  @$pb.TagNumber(7)
  $core.String get lastMsgText => $_getSZ(6);
  @$pb.TagNumber(7)
  set lastMsgText($core.String v) { $_setString(6, v); }

  @$pb.TagNumber(8)
  $fixnum.Int64 get lastMsgTime => $_getI64(7);
  @$pb.TagNumber(8)
  set lastMsgTime($fixnum.Int64 v) { $_setInt64(7, v); }

  @$pb.TagNumber(9)
  $core.bool get isSelf => $_getBF(8);
  @$pb.TagNumber(9)
  set isSelf($core.bool v) { $_setBool(8, v); }

  @$pb.TagNumber(10)
  $core.int get unreadCount => $_getIZ(9);
  @$pb.TagNumber(10)
  set unreadCount($core.int v) { $_setSignedInt32(9, v); }
}

class EngineGetSavedSublistsResponse extends $pb.GeneratedMessage {
  factory EngineGetSavedSublistsResponse({
    $core.Iterable<EngineSavedSublist>? sublists,
    $core.int? totalCount,
  }) {
    final $result = create();
    if (sublists != null) $result.sublists.addAll(sublists);
    if (totalCount != null) $result.totalCount = totalCount;
    return $result;
  }
  EngineGetSavedSublistsResponse._() : super();
  factory EngineGetSavedSublistsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetSavedSublistsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineSavedSublist>(1, _omitFieldNames ? '' : 'sublists', $pb.PbFieldType.PM, subBuilder: EngineSavedSublist.create)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'totalCount', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated('Will be removed in next major version')
  EngineGetSavedSublistsResponse clone() => EngineGetSavedSublistsResponse()..mergeFromMessage(this);
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static EngineGetSavedSublistsResponse create() => EngineGetSavedSublistsResponse._();
  EngineGetSavedSublistsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetSavedSublistsResponse> createRepeated() => $pb.PbList<EngineGetSavedSublistsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSavedSublistsResponse getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EngineGetSavedSublistsResponse>(create);
  static EngineGetSavedSublistsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineSavedSublist> get sublists => $_getList(0);

  @$pb.TagNumber(2)
  $core.int get totalCount => $_getIZ(1);
  @$pb.TagNumber(2)
  set totalCount($core.int v) { $_setSignedInt32(1, v); }
}

class EngineGetSavedReactionTagsRequest extends $pb.GeneratedMessage {
  factory EngineGetSavedReactionTagsRequest({
    $core.String? accountId,
    $core.String? sublistPeerId,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (sublistPeerId != null) {
      $result.sublistPeerId = sublistPeerId;
    }
    return $result;
  }

  EngineGetSavedReactionTagsRequest._() : super();

  factory EngineGetSavedReactionTagsRequest.fromBuffer($core.List<$core.int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);
  factory EngineGetSavedReactionTagsRequest.fromJson($core.String i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineGetSavedReactionTagsRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'sublistPeerId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineGetSavedReactionTagsRequest clone() =>
      EngineGetSavedReactionTagsRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineGetSavedReactionTagsRequest copyWith(
          void Function(EngineGetSavedReactionTagsRequest) updates) =>
      super.copyWith((message) =>
              updates(message as EngineGetSavedReactionTagsRequest))
          as EngineGetSavedReactionTagsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSavedReactionTagsRequest create() =>
      EngineGetSavedReactionTagsRequest._();
  EngineGetSavedReactionTagsRequest createEmptyInstance() => create();
  static $pb.PbList<EngineGetSavedReactionTagsRequest> createRepeated() =>
      $pb.PbList<EngineGetSavedReactionTagsRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSavedReactionTagsRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage
          .$_defaultFor<EngineGetSavedReactionTagsRequest>(create);
  static EngineGetSavedReactionTagsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(2)
  $core.String get sublistPeerId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sublistPeerId($core.String v) {
    $_setString(1, v);
  }
}

class EngineSavedReactionTag extends $pb.GeneratedMessage {
  factory EngineSavedReactionTag({
    $core.String? emoji,
    $fixnum.Int64? customId,
    $core.String? title,
    $core.int? count,
  }) {
    final $result = create();
    if (emoji != null) {
      $result.emoji = emoji;
    }
    if (customId != null) {
      $result.customId = customId;
    }
    if (title != null) {
      $result.title = title;
    }
    if (count != null) {
      $result.count = count;
    }
    return $result;
  }

  EngineSavedReactionTag._() : super();

  factory EngineSavedReactionTag.fromBuffer($core.List<$core.int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);
  factory EngineSavedReactionTag.fromJson($core.String i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineSavedReactionTag',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'emoji')
    ..aInt64(2, _omitFieldNames ? '' : 'customId')
    ..aOS(3, _omitFieldNames ? '' : 'title')
    ..a<$core.int>(4, _omitFieldNames ? '' : 'count', $pb.PbFieldType.O3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineSavedReactionTag clone() =>
      EngineSavedReactionTag()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineSavedReactionTag copyWith(
          void Function(EngineSavedReactionTag) updates) =>
      super.copyWith(
              (message) => updates(message as EngineSavedReactionTag))
          as EngineSavedReactionTag;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSavedReactionTag create() => EngineSavedReactionTag._();
  EngineSavedReactionTag createEmptyInstance() => create();
  static $pb.PbList<EngineSavedReactionTag> createRepeated() =>
      $pb.PbList<EngineSavedReactionTag>();
  @$core.pragma('dart2js:noInline')
  static EngineSavedReactionTag getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineSavedReactionTag>(create);
  static EngineSavedReactionTag? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get emoji => $_getSZ(0);
  @$pb.TagNumber(1)
  set emoji($core.String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(2)
  $fixnum.Int64 get customId => $_getI64(1);
  @$pb.TagNumber(2)
  set customId($fixnum.Int64 v) {
    $_setInt64(1, v);
  }

  @$pb.TagNumber(3)
  $core.String get title => $_getSZ(2);
  @$pb.TagNumber(3)
  set title($core.String v) {
    $_setString(2, v);
  }

  @$pb.TagNumber(4)
  $core.int get count => $_getIZ(3);
  @$pb.TagNumber(4)
  set count($core.int v) {
    $_setSignedInt32(3, v);
  }
}

class EngineGetSavedReactionTagsResponse extends $pb.GeneratedMessage {
  factory EngineGetSavedReactionTagsResponse({
    $core.Iterable<EngineSavedReactionTag>? tags,
  }) {
    final $result = create();
    if (tags != null) {
      $result.tags.addAll(tags);
    }
    return $result;
  }

  EngineGetSavedReactionTagsResponse._() : super();

  factory EngineGetSavedReactionTagsResponse.fromBuffer(
          $core.List<$core.int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);
  factory EngineGetSavedReactionTagsResponse.fromJson($core.String i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineGetSavedReactionTagsResponse',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'),
      createEmptyInstance: create)
    ..pc<EngineSavedReactionTag>(
        1, _omitFieldNames ? '' : 'tags', $pb.PbFieldType.PM,
        subBuilder: EngineSavedReactionTag.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineGetSavedReactionTagsResponse clone() =>
      EngineGetSavedReactionTagsResponse()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineGetSavedReactionTagsResponse copyWith(
          void Function(EngineGetSavedReactionTagsResponse) updates) =>
      super.copyWith((message) =>
              updates(message as EngineGetSavedReactionTagsResponse))
          as EngineGetSavedReactionTagsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineGetSavedReactionTagsResponse create() =>
      EngineGetSavedReactionTagsResponse._();
  EngineGetSavedReactionTagsResponse createEmptyInstance() => create();
  static $pb.PbList<EngineGetSavedReactionTagsResponse> createRepeated() =>
      $pb.PbList<EngineGetSavedReactionTagsResponse>();
  @$core.pragma('dart2js:noInline')
  static EngineGetSavedReactionTagsResponse getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage
          .$_defaultFor<EngineGetSavedReactionTagsResponse>(create);
  static EngineGetSavedReactionTagsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<EngineSavedReactionTag> get tags => $_getList(0);
}

class EngineRenameSavedReactionTagRequest extends $pb.GeneratedMessage {
  factory EngineRenameSavedReactionTagRequest({
    $core.String? accountId,
    $core.String? emoji,
    $fixnum.Int64? customId,
    $core.String? title,
  }) {
    final $result = create();
    if (accountId != null) {
      $result.accountId = accountId;
    }
    if (emoji != null) {
      $result.emoji = emoji;
    }
    if (customId != null) {
      $result.customId = customId;
    }
    if (title != null) {
      $result.title = title;
    }
    return $result;
  }

  EngineRenameSavedReactionTagRequest._() : super();

  factory EngineRenameSavedReactionTagRequest.fromBuffer(
          $core.List<$core.int> i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(i, r);
  factory EngineRenameSavedReactionTagRequest.fromJson($core.String i,
          [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineRenameSavedReactionTagRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'emoji')
    ..aInt64(3, _omitFieldNames ? '' : 'customId')
    ..aOS(4, _omitFieldNames ? '' : 'title')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineRenameSavedReactionTagRequest clone() =>
      EngineRenameSavedReactionTagRequest()..mergeFromMessage(this);
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineRenameSavedReactionTagRequest copyWith(
          void Function(EngineRenameSavedReactionTagRequest) updates) =>
      super.copyWith((message) =>
              updates(message as EngineRenameSavedReactionTagRequest))
          as EngineRenameSavedReactionTagRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineRenameSavedReactionTagRequest create() =>
      EngineRenameSavedReactionTagRequest._();
  EngineRenameSavedReactionTagRequest createEmptyInstance() => create();
  static $pb.PbList<EngineRenameSavedReactionTagRequest> createRepeated() =>
      $pb.PbList<EngineRenameSavedReactionTagRequest>();
  @$core.pragma('dart2js:noInline')
  static EngineRenameSavedReactionTagRequest getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage
          .$_defaultFor<EngineRenameSavedReactionTagRequest>(create);
  static EngineRenameSavedReactionTagRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get accountId => $_getSZ(0);
  @$pb.TagNumber(1)
  set accountId($core.String v) {
    $_setString(0, v);
  }

  @$pb.TagNumber(2)
  $core.String get emoji => $_getSZ(1);
  @$pb.TagNumber(2)
  set emoji($core.String v) {
    $_setString(1, v);
  }

  @$pb.TagNumber(3)
  $fixnum.Int64 get customId => $_getI64(2);
  @$pb.TagNumber(3)
  set customId($fixnum.Int64 v) {
    $_setInt64(2, v);
  }

  @$pb.TagNumber(4)
  $core.String get title => $_getSZ(3);
  @$pb.TagNumber(4)
  set title($core.String v) {
    $_setString(3, v);
  }
}

const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');

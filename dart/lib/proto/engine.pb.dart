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
    return $result;
  }
  EngineMuteChatRequest._() : super();
  factory EngineMuteChatRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineMuteChatRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineMuteChatRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'accountId')
    ..aOS(2, _omitFieldNames ? '' : 'chatId')
    ..aOB(3, _omitFieldNames ? '' : 'muted')
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

class EngineGetForumTopicsResponse extends $pb.GeneratedMessage {
  factory EngineGetForumTopicsResponse({
    $core.Iterable<EngineChatInfo>? chats,
  }) {
    final $result = create();
    if (chats != null) {
      $result.chats.addAll(chats);
    }
    return $result;
  }
  EngineGetForumTopicsResponse._() : super();
  factory EngineGetForumTopicsResponse.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineGetForumTopicsResponse.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineGetForumTopicsResponse', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..pc<EngineChatInfo>(1, _omitFieldNames ? '' : 'chats', $pb.PbFieldType.PM, subBuilder: EngineChatInfo.create)
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
  $core.List<EngineChatInfo> get chats => $_getList(0);
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
  EngineFolderInfo._() : super();
  factory EngineFolderInfo.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EngineFolderInfo.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EngineFolderInfo', package: const $pb.PackageName(_omitMessageNames ? '' : 'uniclient'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..pPS(3, _omitFieldNames ? '' : 'chatIds')
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


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'fs_download_provider.dart';

class FsDownloadStateMapper extends ClassMapperBase<FsDownloadState> {
  FsDownloadStateMapper._();

  static FsDownloadStateMapper? _instance;
  static FsDownloadStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FsDownloadStateMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FsDownloadState';

  static String? _$sessionId(FsDownloadState v) => v.sessionId;
  static const Field<FsDownloadState, String> _f$sessionId = Field(
    'sessionId',
    _$sessionId,
  );
  static String? _$path(FsDownloadState v) => v.path;
  static const Field<FsDownloadState, String> _f$path = Field('path', _$path);
  static String? _$filename(FsDownloadState v) => v.filename;
  static const Field<FsDownloadState, String> _f$filename = Field(
    'filename',
    _$filename,
  );
  static int _$transferred(FsDownloadState v) => v.transferred;
  static const Field<FsDownloadState, int> _f$transferred = Field(
    'transferred',
    _$transferred,
  );
  static int _$total(FsDownloadState v) => v.total;
  static const Field<FsDownloadState, int> _f$total = Field('total', _$total);
  static FsDownloadStatus _$status(FsDownloadState v) => v.status;
  static const Field<FsDownloadState, FsDownloadStatus> _f$status = Field(
    'status',
    _$status,
  );
  static String? _$cachedPath(FsDownloadState v) => v.cachedPath;
  static const Field<FsDownloadState, String> _f$cachedPath = Field(
    'cachedPath',
    _$cachedPath,
  );
  static String? _$destinationPath(FsDownloadState v) => v.destinationPath;
  static const Field<FsDownloadState, String> _f$destinationPath = Field(
    'destinationPath',
    _$destinationPath,
  );
  static String? _$error(FsDownloadState v) => v.error;
  static const Field<FsDownloadState, String> _f$error = Field(
    'error',
    _$error,
  );

  @override
  final MappableFields<FsDownloadState> fields = const {
    #sessionId: _f$sessionId,
    #path: _f$path,
    #filename: _f$filename,
    #transferred: _f$transferred,
    #total: _f$total,
    #status: _f$status,
    #cachedPath: _f$cachedPath,
    #destinationPath: _f$destinationPath,
    #error: _f$error,
  };

  static FsDownloadState _instantiate(DecodingData data) {
    return FsDownloadState(
      sessionId: data.dec(_f$sessionId),
      path: data.dec(_f$path),
      filename: data.dec(_f$filename),
      transferred: data.dec(_f$transferred),
      total: data.dec(_f$total),
      status: data.dec(_f$status),
      cachedPath: data.dec(_f$cachedPath),
      destinationPath: data.dec(_f$destinationPath),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FsDownloadState fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FsDownloadState>(map);
  }

  static FsDownloadState deserialize(String json) {
    return ensureInitialized().decodeJson<FsDownloadState>(json);
  }
}

mixin FsDownloadStateMappable {
  String serialize() {
    return FsDownloadStateMapper.ensureInitialized()
        .encodeJson<FsDownloadState>(this as FsDownloadState);
  }

  Map<String, dynamic> toJson() {
    return FsDownloadStateMapper.ensureInitialized().encodeMap<FsDownloadState>(
      this as FsDownloadState,
    );
  }

  FsDownloadStateCopyWith<FsDownloadState, FsDownloadState, FsDownloadState>
  get copyWith =>
      _FsDownloadStateCopyWithImpl<FsDownloadState, FsDownloadState>(
        this as FsDownloadState,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FsDownloadStateMapper.ensureInitialized().stringifyValue(
      this as FsDownloadState,
    );
  }

  @override
  bool operator ==(Object other) {
    return FsDownloadStateMapper.ensureInitialized().equalsValue(
      this as FsDownloadState,
      other,
    );
  }

  @override
  int get hashCode {
    return FsDownloadStateMapper.ensureInitialized().hashValue(
      this as FsDownloadState,
    );
  }
}

extension FsDownloadStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FsDownloadState, $Out> {
  FsDownloadStateCopyWith<$R, FsDownloadState, $Out> get $asFsDownloadState =>
      $base.as((v, t, t2) => _FsDownloadStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FsDownloadStateCopyWith<$R, $In extends FsDownloadState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    String? sessionId,
    String? path,
    String? filename,
    int? transferred,
    int? total,
    FsDownloadStatus? status,
    String? cachedPath,
    String? destinationPath,
    String? error,
  });
  FsDownloadStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _FsDownloadStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FsDownloadState, $Out>
    implements FsDownloadStateCopyWith<$R, FsDownloadState, $Out> {
  _FsDownloadStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FsDownloadState> $mapper =
      FsDownloadStateMapper.ensureInitialized();
  @override
  $R call({
    Object? sessionId = $none,
    Object? path = $none,
    Object? filename = $none,
    int? transferred,
    int? total,
    FsDownloadStatus? status,
    Object? cachedPath = $none,
    Object? destinationPath = $none,
    Object? error = $none,
  }) => $apply(
    FieldCopyWithData({
      if (sessionId != $none) #sessionId: sessionId,
      if (path != $none) #path: path,
      if (filename != $none) #filename: filename,
      if (transferred != null) #transferred: transferred,
      if (total != null) #total: total,
      if (status != null) #status: status,
      if (cachedPath != $none) #cachedPath: cachedPath,
      if (destinationPath != $none) #destinationPath: destinationPath,
      if (error != $none) #error: error,
    }),
  );
  @override
  FsDownloadState $make(CopyWithData data) => FsDownloadState(
    sessionId: data.get(#sessionId, or: $value.sessionId),
    path: data.get(#path, or: $value.path),
    filename: data.get(#filename, or: $value.filename),
    transferred: data.get(#transferred, or: $value.transferred),
    total: data.get(#total, or: $value.total),
    status: data.get(#status, or: $value.status),
    cachedPath: data.get(#cachedPath, or: $value.cachedPath),
    destinationPath: data.get(#destinationPath, or: $value.destinationPath),
    error: data.get(#error, or: $value.error),
  );

  @override
  FsDownloadStateCopyWith<$R2, FsDownloadState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FsDownloadStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'photo_sync_provider.dart';

class PhotoSyncStateMapper extends ClassMapperBase<PhotoSyncState> {
  PhotoSyncStateMapper._();

  static PhotoSyncStateMapper? _instance;
  static PhotoSyncStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = PhotoSyncStateMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'PhotoSyncState';

  static PhotoSyncPhase _$phase(PhotoSyncState v) => v.phase;
  static const Field<PhotoSyncState, PhotoSyncPhase> _f$phase = Field(
    'phase',
    _$phase,
  );
  static int _$localScannedCount(PhotoSyncState v) => v.localScannedCount;
  static const Field<PhotoSyncState, int> _f$localScannedCount = Field(
    'localScannedCount',
    _$localScannedCount,
  );
  static int _$remoteScannedCount(PhotoSyncState v) => v.remoteScannedCount;
  static const Field<PhotoSyncState, int> _f$remoteScannedCount = Field(
    'remoteScannedCount',
    _$remoteScannedCount,
  );
  static int _$uploadedCount(PhotoSyncState v) => v.uploadedCount;
  static const Field<PhotoSyncState, int> _f$uploadedCount = Field(
    'uploadedCount',
    _$uploadedCount,
  );
  static int _$skippedCount(PhotoSyncState v) => v.skippedCount;
  static const Field<PhotoSyncState, int> _f$skippedCount = Field(
    'skippedCount',
    _$skippedCount,
  );
  static int _$failedCount(PhotoSyncState v) => v.failedCount;
  static const Field<PhotoSyncState, int> _f$failedCount = Field(
    'failedCount',
    _$failedCount,
  );
  static int _$totalToUpload(PhotoSyncState v) => v.totalToUpload;
  static const Field<PhotoSyncState, int> _f$totalToUpload = Field(
    'totalToUpload',
    _$totalToUpload,
  );
  static String? _$currentFilename(PhotoSyncState v) => v.currentFilename;
  static const Field<PhotoSyncState, String> _f$currentFilename = Field(
    'currentFilename',
    _$currentFilename,
    opt: true,
  );
  static String? _$error(PhotoSyncState v) => v.error;
  static const Field<PhotoSyncState, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );

  @override
  final MappableFields<PhotoSyncState> fields = const {
    #phase: _f$phase,
    #localScannedCount: _f$localScannedCount,
    #remoteScannedCount: _f$remoteScannedCount,
    #uploadedCount: _f$uploadedCount,
    #skippedCount: _f$skippedCount,
    #failedCount: _f$failedCount,
    #totalToUpload: _f$totalToUpload,
    #currentFilename: _f$currentFilename,
    #error: _f$error,
  };

  static PhotoSyncState _instantiate(DecodingData data) {
    return PhotoSyncState(
      phase: data.dec(_f$phase),
      localScannedCount: data.dec(_f$localScannedCount),
      remoteScannedCount: data.dec(_f$remoteScannedCount),
      uploadedCount: data.dec(_f$uploadedCount),
      skippedCount: data.dec(_f$skippedCount),
      failedCount: data.dec(_f$failedCount),
      totalToUpload: data.dec(_f$totalToUpload),
      currentFilename: data.dec(_f$currentFilename),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static PhotoSyncState fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<PhotoSyncState>(map);
  }

  static PhotoSyncState deserialize(String json) {
    return ensureInitialized().decodeJson<PhotoSyncState>(json);
  }
}

mixin PhotoSyncStateMappable {
  String serialize() {
    return PhotoSyncStateMapper.ensureInitialized().encodeJson<PhotoSyncState>(
      this as PhotoSyncState,
    );
  }

  Map<String, dynamic> toJson() {
    return PhotoSyncStateMapper.ensureInitialized().encodeMap<PhotoSyncState>(
      this as PhotoSyncState,
    );
  }

  PhotoSyncStateCopyWith<PhotoSyncState, PhotoSyncState, PhotoSyncState>
  get copyWith => _PhotoSyncStateCopyWithImpl<PhotoSyncState, PhotoSyncState>(
    this as PhotoSyncState,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return PhotoSyncStateMapper.ensureInitialized().stringifyValue(
      this as PhotoSyncState,
    );
  }

  @override
  bool operator ==(Object other) {
    return PhotoSyncStateMapper.ensureInitialized().equalsValue(
      this as PhotoSyncState,
      other,
    );
  }

  @override
  int get hashCode {
    return PhotoSyncStateMapper.ensureInitialized().hashValue(
      this as PhotoSyncState,
    );
  }
}

extension PhotoSyncStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, PhotoSyncState, $Out> {
  PhotoSyncStateCopyWith<$R, PhotoSyncState, $Out> get $asPhotoSyncState =>
      $base.as((v, t, t2) => _PhotoSyncStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class PhotoSyncStateCopyWith<$R, $In extends PhotoSyncState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({
    PhotoSyncPhase? phase,
    int? localScannedCount,
    int? remoteScannedCount,
    int? uploadedCount,
    int? skippedCount,
    int? failedCount,
    int? totalToUpload,
    String? currentFilename,
    String? error,
  });
  PhotoSyncStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _PhotoSyncStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, PhotoSyncState, $Out>
    implements PhotoSyncStateCopyWith<$R, PhotoSyncState, $Out> {
  _PhotoSyncStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<PhotoSyncState> $mapper =
      PhotoSyncStateMapper.ensureInitialized();
  @override
  $R call({
    PhotoSyncPhase? phase,
    int? localScannedCount,
    int? remoteScannedCount,
    int? uploadedCount,
    int? skippedCount,
    int? failedCount,
    int? totalToUpload,
    Object? currentFilename = $none,
    Object? error = $none,
  }) => $apply(
    FieldCopyWithData({
      if (phase != null) #phase: phase,
      if (localScannedCount != null) #localScannedCount: localScannedCount,
      if (remoteScannedCount != null) #remoteScannedCount: remoteScannedCount,
      if (uploadedCount != null) #uploadedCount: uploadedCount,
      if (skippedCount != null) #skippedCount: skippedCount,
      if (failedCount != null) #failedCount: failedCount,
      if (totalToUpload != null) #totalToUpload: totalToUpload,
      if (currentFilename != $none) #currentFilename: currentFilename,
      if (error != $none) #error: error,
    }),
  );
  @override
  PhotoSyncState $make(CopyWithData data) => PhotoSyncState(
    phase: data.get(#phase, or: $value.phase),
    localScannedCount: data.get(
      #localScannedCount,
      or: $value.localScannedCount,
    ),
    remoteScannedCount: data.get(
      #remoteScannedCount,
      or: $value.remoteScannedCount,
    ),
    uploadedCount: data.get(#uploadedCount, or: $value.uploadedCount),
    skippedCount: data.get(#skippedCount, or: $value.skippedCount),
    failedCount: data.get(#failedCount, or: $value.failedCount),
    totalToUpload: data.get(#totalToUpload, or: $value.totalToUpload),
    currentFilename: data.get(#currentFilename, or: $value.currentFilename),
    error: data.get(#error, or: $value.error),
  );

  @override
  PhotoSyncStateCopyWith<$R2, PhotoSyncState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _PhotoSyncStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


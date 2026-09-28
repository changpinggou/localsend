// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'fs_upload_provider.dart';

class FsUploadTaskMapper extends ClassMapperBase<FsUploadTask> {
  FsUploadTaskMapper._();

  static FsUploadTaskMapper? _instance;
  static FsUploadTaskMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FsUploadTaskMapper._());
      DeviceMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'FsUploadTask';

  static String _$sessionId(FsUploadTask v) => v.sessionId;
  static const Field<FsUploadTask, String> _f$sessionId = Field(
    'sessionId',
    _$sessionId,
  );
  static String _$localPath(FsUploadTask v) => v.localPath;
  static const Field<FsUploadTask, String> _f$localPath = Field(
    'localPath',
    _$localPath,
  );
  static String _$filename(FsUploadTask v) => v.filename;
  static const Field<FsUploadTask, String> _f$filename = Field(
    'filename',
    _$filename,
  );
  static String _$remotePath(FsUploadTask v) => v.remotePath;
  static const Field<FsUploadTask, String> _f$remotePath = Field(
    'remotePath',
    _$remotePath,
  );
  static int _$total(FsUploadTask v) => v.total;
  static const Field<FsUploadTask, int> _f$total = Field('total', _$total);
  static int _$transferred(FsUploadTask v) => v.transferred;
  static const Field<FsUploadTask, int> _f$transferred = Field(
    'transferred',
    _$transferred,
  );
  static FsUploadStatus _$status(FsUploadTask v) => v.status;
  static const Field<FsUploadTask, FsUploadStatus> _f$status = Field(
    'status',
    _$status,
  );
  static String? _$error(FsUploadTask v) => v.error;
  static const Field<FsUploadTask, String> _f$error = Field('error', _$error);
  static Device _$device(FsUploadTask v) => v.device;
  static const Field<FsUploadTask, Device> _f$device = Field(
    'device',
    _$device,
  );

  @override
  final MappableFields<FsUploadTask> fields = const {
    #sessionId: _f$sessionId,
    #localPath: _f$localPath,
    #filename: _f$filename,
    #remotePath: _f$remotePath,
    #total: _f$total,
    #transferred: _f$transferred,
    #status: _f$status,
    #error: _f$error,
    #device: _f$device,
  };

  static FsUploadTask _instantiate(DecodingData data) {
    return FsUploadTask(
      sessionId: data.dec(_f$sessionId),
      localPath: data.dec(_f$localPath),
      filename: data.dec(_f$filename),
      remotePath: data.dec(_f$remotePath),
      total: data.dec(_f$total),
      transferred: data.dec(_f$transferred),
      status: data.dec(_f$status),
      error: data.dec(_f$error),
      device: data.dec(_f$device),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FsUploadTask fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FsUploadTask>(map);
  }

  static FsUploadTask deserialize(String json) {
    return ensureInitialized().decodeJson<FsUploadTask>(json);
  }
}

mixin FsUploadTaskMappable {
  String serialize() {
    return FsUploadTaskMapper.ensureInitialized().encodeJson<FsUploadTask>(
      this as FsUploadTask,
    );
  }

  Map<String, dynamic> toJson() {
    return FsUploadTaskMapper.ensureInitialized().encodeMap<FsUploadTask>(
      this as FsUploadTask,
    );
  }

  FsUploadTaskCopyWith<FsUploadTask, FsUploadTask, FsUploadTask> get copyWith =>
      _FsUploadTaskCopyWithImpl<FsUploadTask, FsUploadTask>(
        this as FsUploadTask,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FsUploadTaskMapper.ensureInitialized().stringifyValue(
      this as FsUploadTask,
    );
  }

  @override
  bool operator ==(Object other) {
    return FsUploadTaskMapper.ensureInitialized().equalsValue(
      this as FsUploadTask,
      other,
    );
  }

  @override
  int get hashCode {
    return FsUploadTaskMapper.ensureInitialized().hashValue(
      this as FsUploadTask,
    );
  }
}

extension FsUploadTaskValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FsUploadTask, $Out> {
  FsUploadTaskCopyWith<$R, FsUploadTask, $Out> get $asFsUploadTask =>
      $base.as((v, t, t2) => _FsUploadTaskCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FsUploadTaskCopyWith<$R, $In extends FsUploadTask, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  DeviceCopyWith<$R, Device, Device> get device;
  $R call({
    String? sessionId,
    String? localPath,
    String? filename,
    String? remotePath,
    int? total,
    int? transferred,
    FsUploadStatus? status,
    String? error,
    Device? device,
  });
  FsUploadTaskCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FsUploadTaskCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FsUploadTask, $Out>
    implements FsUploadTaskCopyWith<$R, FsUploadTask, $Out> {
  _FsUploadTaskCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FsUploadTask> $mapper =
      FsUploadTaskMapper.ensureInitialized();
  @override
  DeviceCopyWith<$R, Device, Device> get device =>
      $value.device.copyWith.$chain((v) => call(device: v));
  @override
  $R call({
    String? sessionId,
    String? localPath,
    String? filename,
    String? remotePath,
    int? total,
    int? transferred,
    FsUploadStatus? status,
    Object? error = $none,
    Device? device,
  }) => $apply(
    FieldCopyWithData({
      if (sessionId != null) #sessionId: sessionId,
      if (localPath != null) #localPath: localPath,
      if (filename != null) #filename: filename,
      if (remotePath != null) #remotePath: remotePath,
      if (total != null) #total: total,
      if (transferred != null) #transferred: transferred,
      if (status != null) #status: status,
      if (error != $none) #error: error,
      if (device != null) #device: device,
    }),
  );
  @override
  FsUploadTask $make(CopyWithData data) => FsUploadTask(
    sessionId: data.get(#sessionId, or: $value.sessionId),
    localPath: data.get(#localPath, or: $value.localPath),
    filename: data.get(#filename, or: $value.filename),
    remotePath: data.get(#remotePath, or: $value.remotePath),
    total: data.get(#total, or: $value.total),
    transferred: data.get(#transferred, or: $value.transferred),
    status: data.get(#status, or: $value.status),
    error: data.get(#error, or: $value.error),
    device: data.get(#device, or: $value.device),
  );

  @override
  FsUploadTaskCopyWith<$R2, FsUploadTask, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FsUploadTaskCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class FsUploadStateMapper extends ClassMapperBase<FsUploadState> {
  FsUploadStateMapper._();

  static FsUploadStateMapper? _instance;
  static FsUploadStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FsUploadStateMapper._());
      FsUploadTaskMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'FsUploadState';

  static List<FsUploadTask> _$tasks(FsUploadState v) => v.tasks;
  static const Field<FsUploadState, List<FsUploadTask>> _f$tasks = Field(
    'tasks',
    _$tasks,
  );

  @override
  final MappableFields<FsUploadState> fields = const {#tasks: _f$tasks};

  static FsUploadState _instantiate(DecodingData data) {
    return FsUploadState(tasks: data.dec(_f$tasks));
  }

  @override
  final Function instantiate = _instantiate;

  static FsUploadState fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FsUploadState>(map);
  }

  static FsUploadState deserialize(String json) {
    return ensureInitialized().decodeJson<FsUploadState>(json);
  }
}

mixin FsUploadStateMappable {
  String serialize() {
    return FsUploadStateMapper.ensureInitialized().encodeJson<FsUploadState>(
      this as FsUploadState,
    );
  }

  Map<String, dynamic> toJson() {
    return FsUploadStateMapper.ensureInitialized().encodeMap<FsUploadState>(
      this as FsUploadState,
    );
  }

  FsUploadStateCopyWith<FsUploadState, FsUploadState, FsUploadState>
  get copyWith => _FsUploadStateCopyWithImpl<FsUploadState, FsUploadState>(
    this as FsUploadState,
    $identity,
    $identity,
  );
  @override
  String toString() {
    return FsUploadStateMapper.ensureInitialized().stringifyValue(
      this as FsUploadState,
    );
  }

  @override
  bool operator ==(Object other) {
    return FsUploadStateMapper.ensureInitialized().equalsValue(
      this as FsUploadState,
      other,
    );
  }

  @override
  int get hashCode {
    return FsUploadStateMapper.ensureInitialized().hashValue(
      this as FsUploadState,
    );
  }
}

extension FsUploadStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FsUploadState, $Out> {
  FsUploadStateCopyWith<$R, FsUploadState, $Out> get $asFsUploadState =>
      $base.as((v, t, t2) => _FsUploadStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FsUploadStateCopyWith<$R, $In extends FsUploadState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    FsUploadTask,
    FsUploadTaskCopyWith<$R, FsUploadTask, FsUploadTask>
  >
  get tasks;
  $R call({List<FsUploadTask>? tasks});
  FsUploadStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FsUploadStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FsUploadState, $Out>
    implements FsUploadStateCopyWith<$R, FsUploadState, $Out> {
  _FsUploadStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FsUploadState> $mapper =
      FsUploadStateMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    FsUploadTask,
    FsUploadTaskCopyWith<$R, FsUploadTask, FsUploadTask>
  >
  get tasks => ListCopyWith(
    $value.tasks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(tasks: v),
  );
  @override
  $R call({List<FsUploadTask>? tasks}) =>
      $apply(FieldCopyWithData({if (tasks != null) #tasks: tasks}));
  @override
  FsUploadState $make(CopyWithData data) =>
      FsUploadState(tasks: data.get(#tasks, or: $value.tasks));

  @override
  FsUploadStateCopyWith<$R2, FsUploadState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FsUploadStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


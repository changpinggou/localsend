// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'fs_list_provider.dart';

class FsListStateMapper extends ClassMapperBase<FsListState> {
  FsListStateMapper._();

  static FsListStateMapper? _instance;
  static FsListStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FsListStateMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FsListState';

  static String? _$deviceFingerprint(FsListState v) => v.deviceFingerprint;
  static const Field<FsListState, String> _f$deviceFingerprint = Field(
    'deviceFingerprint',
    _$deviceFingerprint,
  );
  static String _$currentPath(FsListState v) => v.currentPath;
  static const Field<FsListState, String> _f$currentPath = Field(
    'currentPath',
    _$currentPath,
  );
  static List<rust_model.FsRoot> _$roots(FsListState v) => v.roots;
  static const Field<FsListState, List<rust_model.FsRoot>> _f$roots = Field(
    'roots',
    _$roots,
  );
  static List<rust_model.FsEntry> _$entries(FsListState v) => v.entries;
  static const Field<FsListState, List<rust_model.FsEntry>> _f$entries = Field(
    'entries',
    _$entries,
  );
  static int _$total(FsListState v) => v.total;
  static const Field<FsListState, int> _f$total = Field('total', _$total);
  static bool _$loading(FsListState v) => v.loading;
  static const Field<FsListState, bool> _f$loading = Field(
    'loading',
    _$loading,
  );
  static bool _$hasMore(FsListState v) => v.hasMore;
  static const Field<FsListState, bool> _f$hasMore = Field(
    'hasMore',
    _$hasMore,
  );
  static int _$page(FsListState v) => v.page;
  static const Field<FsListState, int> _f$page = Field('page', _$page);
  static FsSort _$sort(FsListState v) => v.sort;
  static const Field<FsListState, FsSort> _f$sort = Field('sort', _$sort);
  static FsViewMode _$viewMode(FsListState v) => v.viewMode;
  static const Field<FsListState, FsViewMode> _f$viewMode = Field(
    'viewMode',
    _$viewMode,
  );
  static String? _$error(FsListState v) => v.error;
  static const Field<FsListState, String> _f$error = Field('error', _$error);
  static FsErrorReason? _$errorReason(FsListState v) => v.errorReason;
  static const Field<FsListState, FsErrorReason> _f$errorReason = Field(
    'errorReason',
    _$errorReason,
  );

  @override
  final MappableFields<FsListState> fields = const {
    #deviceFingerprint: _f$deviceFingerprint,
    #currentPath: _f$currentPath,
    #roots: _f$roots,
    #entries: _f$entries,
    #total: _f$total,
    #loading: _f$loading,
    #hasMore: _f$hasMore,
    #page: _f$page,
    #sort: _f$sort,
    #viewMode: _f$viewMode,
    #error: _f$error,
    #errorReason: _f$errorReason,
  };

  static FsListState _instantiate(DecodingData data) {
    return FsListState(
      deviceFingerprint: data.dec(_f$deviceFingerprint),
      currentPath: data.dec(_f$currentPath),
      roots: data.dec(_f$roots),
      entries: data.dec(_f$entries),
      total: data.dec(_f$total),
      loading: data.dec(_f$loading),
      hasMore: data.dec(_f$hasMore),
      page: data.dec(_f$page),
      sort: data.dec(_f$sort),
      viewMode: data.dec(_f$viewMode),
      error: data.dec(_f$error),
      errorReason: data.dec(_f$errorReason),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FsListState fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FsListState>(map);
  }

  static FsListState deserialize(String json) {
    return ensureInitialized().decodeJson<FsListState>(json);
  }
}

mixin FsListStateMappable {
  String serialize() {
    return FsListStateMapper.ensureInitialized().encodeJson<FsListState>(
      this as FsListState,
    );
  }

  Map<String, dynamic> toJson() {
    return FsListStateMapper.ensureInitialized().encodeMap<FsListState>(
      this as FsListState,
    );
  }

  FsListStateCopyWith<FsListState, FsListState, FsListState> get copyWith =>
      _FsListStateCopyWithImpl<FsListState, FsListState>(
        this as FsListState,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FsListStateMapper.ensureInitialized().stringifyValue(
      this as FsListState,
    );
  }

  @override
  bool operator ==(Object other) {
    return FsListStateMapper.ensureInitialized().equalsValue(
      this as FsListState,
      other,
    );
  }

  @override
  int get hashCode {
    return FsListStateMapper.ensureInitialized().hashValue(this as FsListState);
  }
}

extension FsListStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FsListState, $Out> {
  FsListStateCopyWith<$R, FsListState, $Out> get $asFsListState =>
      $base.as((v, t, t2) => _FsListStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FsListStateCopyWith<$R, $In extends FsListState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<
    $R,
    rust_model.FsRoot,
    ObjectCopyWith<$R, rust_model.FsRoot, rust_model.FsRoot>
  >
  get roots;
  ListCopyWith<
    $R,
    rust_model.FsEntry,
    ObjectCopyWith<$R, rust_model.FsEntry, rust_model.FsEntry>
  >
  get entries;
  $R call({
    String? deviceFingerprint,
    String? currentPath,
    List<rust_model.FsRoot>? roots,
    List<rust_model.FsEntry>? entries,
    int? total,
    bool? loading,
    bool? hasMore,
    int? page,
    FsSort? sort,
    FsViewMode? viewMode,
    String? error,
    FsErrorReason? errorReason,
  });
  FsListStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FsListStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FsListState, $Out>
    implements FsListStateCopyWith<$R, FsListState, $Out> {
  _FsListStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FsListState> $mapper =
      FsListStateMapper.ensureInitialized();
  @override
  ListCopyWith<
    $R,
    rust_model.FsRoot,
    ObjectCopyWith<$R, rust_model.FsRoot, rust_model.FsRoot>
  >
  get roots => ListCopyWith(
    $value.roots,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(roots: v),
  );
  @override
  ListCopyWith<
    $R,
    rust_model.FsEntry,
    ObjectCopyWith<$R, rust_model.FsEntry, rust_model.FsEntry>
  >
  get entries => ListCopyWith(
    $value.entries,
    (v, t) => ObjectCopyWith(v, $identity, t),
    (v) => call(entries: v),
  );
  @override
  $R call({
    Object? deviceFingerprint = $none,
    String? currentPath,
    List<rust_model.FsRoot>? roots,
    List<rust_model.FsEntry>? entries,
    int? total,
    bool? loading,
    bool? hasMore,
    int? page,
    FsSort? sort,
    FsViewMode? viewMode,
    Object? error = $none,
    Object? errorReason = $none,
  }) => $apply(
    FieldCopyWithData({
      if (deviceFingerprint != $none) #deviceFingerprint: deviceFingerprint,
      if (currentPath != null) #currentPath: currentPath,
      if (roots != null) #roots: roots,
      if (entries != null) #entries: entries,
      if (total != null) #total: total,
      if (loading != null) #loading: loading,
      if (hasMore != null) #hasMore: hasMore,
      if (page != null) #page: page,
      if (sort != null) #sort: sort,
      if (viewMode != null) #viewMode: viewMode,
      if (error != $none) #error: error,
      if (errorReason != $none) #errorReason: errorReason,
    }),
  );
  @override
  FsListState $make(CopyWithData data) => FsListState(
    deviceFingerprint: data.get(
      #deviceFingerprint,
      or: $value.deviceFingerprint,
    ),
    currentPath: data.get(#currentPath, or: $value.currentPath),
    roots: data.get(#roots, or: $value.roots),
    entries: data.get(#entries, or: $value.entries),
    total: data.get(#total, or: $value.total),
    loading: data.get(#loading, or: $value.loading),
    hasMore: data.get(#hasMore, or: $value.hasMore),
    page: data.get(#page, or: $value.page),
    sort: data.get(#sort, or: $value.sort),
    viewMode: data.get(#viewMode, or: $value.viewMode),
    error: data.get(#error, or: $value.error),
    errorReason: data.get(#errorReason, or: $value.errorReason),
  );

  @override
  FsListStateCopyWith<$R2, FsListState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FsListStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


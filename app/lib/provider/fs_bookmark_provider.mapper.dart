// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
// ignore_for_file: type=lint
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: unused_element, unnecessary_cast, override_on_non_overriding_member
// ignore_for_file: strict_raw_type, inference_failure_on_untyped_parameter

part of 'fs_bookmark_provider.dart';

class FsBookmarkMapper extends ClassMapperBase<FsBookmark> {
  FsBookmarkMapper._();

  static FsBookmarkMapper? _instance;
  static FsBookmarkMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FsBookmarkMapper._());
    }
    return _instance!;
  }

  @override
  final String id = 'FsBookmark';

  static String _$path(FsBookmark v) => v.path;
  static const Field<FsBookmark, String> _f$path = Field('path', _$path);
  static String? _$alias(FsBookmark v) => v.alias;
  static const Field<FsBookmark, String> _f$alias = Field(
    'alias',
    _$alias,
    opt: true,
  );
  static DateTime _$createdAt(FsBookmark v) => v.createdAt;
  static const Field<FsBookmark, DateTime> _f$createdAt = Field(
    'createdAt',
    _$createdAt,
  );

  @override
  final MappableFields<FsBookmark> fields = const {
    #path: _f$path,
    #alias: _f$alias,
    #createdAt: _f$createdAt,
  };

  static FsBookmark _instantiate(DecodingData data) {
    return FsBookmark(
      path: data.dec(_f$path),
      alias: data.dec(_f$alias),
      createdAt: data.dec(_f$createdAt),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FsBookmark fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FsBookmark>(map);
  }

  static FsBookmark deserialize(String json) {
    return ensureInitialized().decodeJson<FsBookmark>(json);
  }
}

mixin FsBookmarkMappable {
  String serialize() {
    return FsBookmarkMapper.ensureInitialized().encodeJson<FsBookmark>(
      this as FsBookmark,
    );
  }

  Map<String, dynamic> toJson() {
    return FsBookmarkMapper.ensureInitialized().encodeMap<FsBookmark>(
      this as FsBookmark,
    );
  }

  FsBookmarkCopyWith<FsBookmark, FsBookmark, FsBookmark> get copyWith =>
      _FsBookmarkCopyWithImpl<FsBookmark, FsBookmark>(
        this as FsBookmark,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FsBookmarkMapper.ensureInitialized().stringifyValue(
      this as FsBookmark,
    );
  }

  @override
  bool operator ==(Object other) {
    return FsBookmarkMapper.ensureInitialized().equalsValue(
      this as FsBookmark,
      other,
    );
  }

  @override
  int get hashCode {
    return FsBookmarkMapper.ensureInitialized().hashValue(this as FsBookmark);
  }
}

extension FsBookmarkValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FsBookmark, $Out> {
  FsBookmarkCopyWith<$R, FsBookmark, $Out> get $asFsBookmark =>
      $base.as((v, t, t2) => _FsBookmarkCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FsBookmarkCopyWith<$R, $In extends FsBookmark, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  $R call({String? path, String? alias, DateTime? createdAt});
  FsBookmarkCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(Then<$Out2, $R2> t);
}

class _FsBookmarkCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FsBookmark, $Out>
    implements FsBookmarkCopyWith<$R, FsBookmark, $Out> {
  _FsBookmarkCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FsBookmark> $mapper =
      FsBookmarkMapper.ensureInitialized();
  @override
  $R call({String? path, Object? alias = $none, DateTime? createdAt}) => $apply(
    FieldCopyWithData({
      if (path != null) #path: path,
      if (alias != $none) #alias: alias,
      if (createdAt != null) #createdAt: createdAt,
    }),
  );
  @override
  FsBookmark $make(CopyWithData data) => FsBookmark(
    path: data.get(#path, or: $value.path),
    alias: data.get(#alias, or: $value.alias),
    createdAt: data.get(#createdAt, or: $value.createdAt),
  );

  @override
  FsBookmarkCopyWith<$R2, FsBookmark, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FsBookmarkCopyWithImpl<$R2, $Out2>($value, $cast, t);
}

class FsBookmarkStateMapper extends ClassMapperBase<FsBookmarkState> {
  FsBookmarkStateMapper._();

  static FsBookmarkStateMapper? _instance;
  static FsBookmarkStateMapper ensureInitialized() {
    if (_instance == null) {
      MapperContainer.globals.use(_instance = FsBookmarkStateMapper._());
      FsBookmarkMapper.ensureInitialized();
    }
    return _instance!;
  }

  @override
  final String id = 'FsBookmarkState';

  static List<FsBookmark> _$bookmarks(FsBookmarkState v) => v.bookmarks;
  static const Field<FsBookmarkState, List<FsBookmark>> _f$bookmarks = Field(
    'bookmarks',
    _$bookmarks,
  );
  static bool _$loading(FsBookmarkState v) => v.loading;
  static const Field<FsBookmarkState, bool> _f$loading = Field(
    'loading',
    _$loading,
  );
  static String? _$error(FsBookmarkState v) => v.error;
  static const Field<FsBookmarkState, String> _f$error = Field(
    'error',
    _$error,
    opt: true,
  );

  @override
  final MappableFields<FsBookmarkState> fields = const {
    #bookmarks: _f$bookmarks,
    #loading: _f$loading,
    #error: _f$error,
  };

  static FsBookmarkState _instantiate(DecodingData data) {
    return FsBookmarkState(
      bookmarks: data.dec(_f$bookmarks),
      loading: data.dec(_f$loading),
      error: data.dec(_f$error),
    );
  }

  @override
  final Function instantiate = _instantiate;

  static FsBookmarkState fromJson(Map<String, dynamic> map) {
    return ensureInitialized().decodeMap<FsBookmarkState>(map);
  }

  static FsBookmarkState deserialize(String json) {
    return ensureInitialized().decodeJson<FsBookmarkState>(json);
  }
}

mixin FsBookmarkStateMappable {
  String serialize() {
    return FsBookmarkStateMapper.ensureInitialized()
        .encodeJson<FsBookmarkState>(this as FsBookmarkState);
  }

  Map<String, dynamic> toJson() {
    return FsBookmarkStateMapper.ensureInitialized().encodeMap<FsBookmarkState>(
      this as FsBookmarkState,
    );
  }

  FsBookmarkStateCopyWith<FsBookmarkState, FsBookmarkState, FsBookmarkState>
  get copyWith =>
      _FsBookmarkStateCopyWithImpl<FsBookmarkState, FsBookmarkState>(
        this as FsBookmarkState,
        $identity,
        $identity,
      );
  @override
  String toString() {
    return FsBookmarkStateMapper.ensureInitialized().stringifyValue(
      this as FsBookmarkState,
    );
  }

  @override
  bool operator ==(Object other) {
    return FsBookmarkStateMapper.ensureInitialized().equalsValue(
      this as FsBookmarkState,
      other,
    );
  }

  @override
  int get hashCode {
    return FsBookmarkStateMapper.ensureInitialized().hashValue(
      this as FsBookmarkState,
    );
  }
}

extension FsBookmarkStateValueCopy<$R, $Out>
    on ObjectCopyWith<$R, FsBookmarkState, $Out> {
  FsBookmarkStateCopyWith<$R, FsBookmarkState, $Out> get $asFsBookmarkState =>
      $base.as((v, t, t2) => _FsBookmarkStateCopyWithImpl<$R, $Out>(v, t, t2));
}

abstract class FsBookmarkStateCopyWith<$R, $In extends FsBookmarkState, $Out>
    implements ClassCopyWith<$R, $In, $Out> {
  ListCopyWith<$R, FsBookmark, FsBookmarkCopyWith<$R, FsBookmark, FsBookmark>>
  get bookmarks;
  $R call({List<FsBookmark>? bookmarks, bool? loading, String? error});
  FsBookmarkStateCopyWith<$R2, $In, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  );
}

class _FsBookmarkStateCopyWithImpl<$R, $Out>
    extends ClassCopyWithBase<$R, FsBookmarkState, $Out>
    implements FsBookmarkStateCopyWith<$R, FsBookmarkState, $Out> {
  _FsBookmarkStateCopyWithImpl(super.value, super.then, super.then2);

  @override
  late final ClassMapperBase<FsBookmarkState> $mapper =
      FsBookmarkStateMapper.ensureInitialized();
  @override
  ListCopyWith<$R, FsBookmark, FsBookmarkCopyWith<$R, FsBookmark, FsBookmark>>
  get bookmarks => ListCopyWith(
    $value.bookmarks,
    (v, t) => v.copyWith.$chain(t),
    (v) => call(bookmarks: v),
  );
  @override
  $R call({
    List<FsBookmark>? bookmarks,
    bool? loading,
    Object? error = $none,
  }) => $apply(
    FieldCopyWithData({
      if (bookmarks != null) #bookmarks: bookmarks,
      if (loading != null) #loading: loading,
      if (error != $none) #error: error,
    }),
  );
  @override
  FsBookmarkState $make(CopyWithData data) => FsBookmarkState(
    bookmarks: data.get(#bookmarks, or: $value.bookmarks),
    loading: data.get(#loading, or: $value.loading),
    error: data.get(#error, or: $value.error),
  );

  @override
  FsBookmarkStateCopyWith<$R2, FsBookmarkState, $Out2> $chain<$R2, $Out2>(
    Then<$Out2, $R2> t,
  ) => _FsBookmarkStateCopyWithImpl<$R2, $Out2>($value, $cast, t);
}


// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'http.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RsFsDownloadEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsFsDownloadEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsFsDownloadEvent()';
}


}

/// @nodoc
class $RsFsDownloadEventCopyWith<$Res>  {
$RsFsDownloadEventCopyWith(RsFsDownloadEvent _, $Res Function(RsFsDownloadEvent) __);
}


/// Adds pattern-matching-related methods to [RsFsDownloadEvent].
extension RsFsDownloadEventPatterns on RsFsDownloadEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsFsDownloadEvent_Started value)?  started,TResult Function( RsFsDownloadEvent_Chunk value)?  chunk,TResult Function( RsFsDownloadEvent_Finished value)?  finished,TResult Function( RsFsDownloadEvent_Cancelled value)?  cancelled,TResult Function( RsFsDownloadEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsFsDownloadEvent_Started() when started != null:
return started(_that);case RsFsDownloadEvent_Chunk() when chunk != null:
return chunk(_that);case RsFsDownloadEvent_Finished() when finished != null:
return finished(_that);case RsFsDownloadEvent_Cancelled() when cancelled != null:
return cancelled(_that);case RsFsDownloadEvent_Failed() when failed != null:
return failed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsFsDownloadEvent_Started value)  started,required TResult Function( RsFsDownloadEvent_Chunk value)  chunk,required TResult Function( RsFsDownloadEvent_Finished value)  finished,required TResult Function( RsFsDownloadEvent_Cancelled value)  cancelled,required TResult Function( RsFsDownloadEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case RsFsDownloadEvent_Started():
return started(_that);case RsFsDownloadEvent_Chunk():
return chunk(_that);case RsFsDownloadEvent_Finished():
return finished(_that);case RsFsDownloadEvent_Cancelled():
return cancelled(_that);case RsFsDownloadEvent_Failed():
return failed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsFsDownloadEvent_Started value)?  started,TResult? Function( RsFsDownloadEvent_Chunk value)?  chunk,TResult? Function( RsFsDownloadEvent_Finished value)?  finished,TResult? Function( RsFsDownloadEvent_Cancelled value)?  cancelled,TResult? Function( RsFsDownloadEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case RsFsDownloadEvent_Started() when started != null:
return started(_that);case RsFsDownloadEvent_Chunk() when chunk != null:
return chunk(_that);case RsFsDownloadEvent_Finished() when finished != null:
return finished(_that);case RsFsDownloadEvent_Cancelled() when cancelled != null:
return cancelled(_that);case RsFsDownloadEvent_Failed() when failed != null:
return failed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BigInt totalSize,  int status)?  started,TResult Function( Uint8List bytes,  BigInt transferred)?  chunk,TResult Function()?  finished,TResult Function()?  cancelled,TResult Function( RsHttpClientError error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsFsDownloadEvent_Started() when started != null:
return started(_that.totalSize,_that.status);case RsFsDownloadEvent_Chunk() when chunk != null:
return chunk(_that.bytes,_that.transferred);case RsFsDownloadEvent_Finished() when finished != null:
return finished();case RsFsDownloadEvent_Cancelled() when cancelled != null:
return cancelled();case RsFsDownloadEvent_Failed() when failed != null:
return failed(_that.error);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BigInt totalSize,  int status)  started,required TResult Function( Uint8List bytes,  BigInt transferred)  chunk,required TResult Function()  finished,required TResult Function()  cancelled,required TResult Function( RsHttpClientError error)  failed,}) {final _that = this;
switch (_that) {
case RsFsDownloadEvent_Started():
return started(_that.totalSize,_that.status);case RsFsDownloadEvent_Chunk():
return chunk(_that.bytes,_that.transferred);case RsFsDownloadEvent_Finished():
return finished();case RsFsDownloadEvent_Cancelled():
return cancelled();case RsFsDownloadEvent_Failed():
return failed(_that.error);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BigInt totalSize,  int status)?  started,TResult? Function( Uint8List bytes,  BigInt transferred)?  chunk,TResult? Function()?  finished,TResult? Function()?  cancelled,TResult? Function( RsHttpClientError error)?  failed,}) {final _that = this;
switch (_that) {
case RsFsDownloadEvent_Started() when started != null:
return started(_that.totalSize,_that.status);case RsFsDownloadEvent_Chunk() when chunk != null:
return chunk(_that.bytes,_that.transferred);case RsFsDownloadEvent_Finished() when finished != null:
return finished();case RsFsDownloadEvent_Cancelled() when cancelled != null:
return cancelled();case RsFsDownloadEvent_Failed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class RsFsDownloadEvent_Started extends RsFsDownloadEvent {
  const RsFsDownloadEvent_Started({required this.totalSize, required this.status}): super._();
  

 final  BigInt totalSize;
 final  int status;

/// Create a copy of RsFsDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsFsDownloadEvent_StartedCopyWith<RsFsDownloadEvent_Started> get copyWith => _$RsFsDownloadEvent_StartedCopyWithImpl<RsFsDownloadEvent_Started>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsFsDownloadEvent_Started&&(identical(other.totalSize, totalSize) || other.totalSize == totalSize)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode => Object.hash(runtimeType,totalSize,status);

@override
String toString() {
  return 'RsFsDownloadEvent.started(totalSize: $totalSize, status: $status)';
}


}

/// @nodoc
abstract mixin class $RsFsDownloadEvent_StartedCopyWith<$Res> implements $RsFsDownloadEventCopyWith<$Res> {
  factory $RsFsDownloadEvent_StartedCopyWith(RsFsDownloadEvent_Started value, $Res Function(RsFsDownloadEvent_Started) _then) = _$RsFsDownloadEvent_StartedCopyWithImpl;
@useResult
$Res call({
 BigInt totalSize, int status
});




}
/// @nodoc
class _$RsFsDownloadEvent_StartedCopyWithImpl<$Res>
    implements $RsFsDownloadEvent_StartedCopyWith<$Res> {
  _$RsFsDownloadEvent_StartedCopyWithImpl(this._self, this._then);

  final RsFsDownloadEvent_Started _self;
  final $Res Function(RsFsDownloadEvent_Started) _then;

/// Create a copy of RsFsDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? totalSize = null,Object? status = null,}) {
  return _then(RsFsDownloadEvent_Started(
totalSize: null == totalSize ? _self.totalSize : totalSize // ignore: cast_nullable_to_non_nullable
as BigInt,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class RsFsDownloadEvent_Chunk extends RsFsDownloadEvent {
  const RsFsDownloadEvent_Chunk({required this.bytes, required this.transferred}): super._();
  

 final  Uint8List bytes;
 final  BigInt transferred;

/// Create a copy of RsFsDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsFsDownloadEvent_ChunkCopyWith<RsFsDownloadEvent_Chunk> get copyWith => _$RsFsDownloadEvent_ChunkCopyWithImpl<RsFsDownloadEvent_Chunk>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsFsDownloadEvent_Chunk&&const DeepCollectionEquality().equals(other.bytes, bytes)&&(identical(other.transferred, transferred) || other.transferred == transferred));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(bytes),transferred);

@override
String toString() {
  return 'RsFsDownloadEvent.chunk(bytes: $bytes, transferred: $transferred)';
}


}

/// @nodoc
abstract mixin class $RsFsDownloadEvent_ChunkCopyWith<$Res> implements $RsFsDownloadEventCopyWith<$Res> {
  factory $RsFsDownloadEvent_ChunkCopyWith(RsFsDownloadEvent_Chunk value, $Res Function(RsFsDownloadEvent_Chunk) _then) = _$RsFsDownloadEvent_ChunkCopyWithImpl;
@useResult
$Res call({
 Uint8List bytes, BigInt transferred
});




}
/// @nodoc
class _$RsFsDownloadEvent_ChunkCopyWithImpl<$Res>
    implements $RsFsDownloadEvent_ChunkCopyWith<$Res> {
  _$RsFsDownloadEvent_ChunkCopyWithImpl(this._self, this._then);

  final RsFsDownloadEvent_Chunk _self;
  final $Res Function(RsFsDownloadEvent_Chunk) _then;

/// Create a copy of RsFsDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? bytes = null,Object? transferred = null,}) {
  return _then(RsFsDownloadEvent_Chunk(
bytes: null == bytes ? _self.bytes : bytes // ignore: cast_nullable_to_non_nullable
as Uint8List,transferred: null == transferred ? _self.transferred : transferred // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RsFsDownloadEvent_Finished extends RsFsDownloadEvent {
  const RsFsDownloadEvent_Finished(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsFsDownloadEvent_Finished);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsFsDownloadEvent.finished()';
}


}




/// @nodoc


class RsFsDownloadEvent_Cancelled extends RsFsDownloadEvent {
  const RsFsDownloadEvent_Cancelled(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsFsDownloadEvent_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsFsDownloadEvent.cancelled()';
}


}




/// @nodoc


class RsFsDownloadEvent_Failed extends RsFsDownloadEvent {
  const RsFsDownloadEvent_Failed({required this.error}): super._();
  

 final  RsHttpClientError error;

/// Create a copy of RsFsDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsFsDownloadEvent_FailedCopyWith<RsFsDownloadEvent_Failed> get copyWith => _$RsFsDownloadEvent_FailedCopyWithImpl<RsFsDownloadEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsFsDownloadEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'RsFsDownloadEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $RsFsDownloadEvent_FailedCopyWith<$Res> implements $RsFsDownloadEventCopyWith<$Res> {
  factory $RsFsDownloadEvent_FailedCopyWith(RsFsDownloadEvent_Failed value, $Res Function(RsFsDownloadEvent_Failed) _then) = _$RsFsDownloadEvent_FailedCopyWithImpl;
@useResult
$Res call({
 RsHttpClientError error
});


$RsHttpClientErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$RsFsDownloadEvent_FailedCopyWithImpl<$Res>
    implements $RsFsDownloadEvent_FailedCopyWith<$Res> {
  _$RsFsDownloadEvent_FailedCopyWithImpl(this._self, this._then);

  final RsFsDownloadEvent_Failed _self;
  final $Res Function(RsFsDownloadEvent_Failed) _then;

/// Create a copy of RsFsDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(RsFsDownloadEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as RsHttpClientError,
  ));
}

/// Create a copy of RsFsDownloadEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RsHttpClientErrorCopyWith<$Res> get error {
  
  return $RsHttpClientErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$RsHttpClientError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsHttpClientError()';
}


}

/// @nodoc
class $RsHttpClientErrorCopyWith<$Res>  {
$RsHttpClientErrorCopyWith(RsHttpClientError _, $Res Function(RsHttpClientError) __);
}


/// Adds pattern-matching-related methods to [RsHttpClientError].
extension RsHttpClientErrorPatterns on RsHttpClientError {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsHttpClientError_StatusCode value)?  statusCode,TResult Function( RsHttpClientError_Reqwest value)?  reqwest,TResult Function( RsHttpClientError_Json value)?  json,TResult Function( RsHttpClientError_Io value)?  io,TResult Function( RsHttpClientError_Other value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that);case RsHttpClientError_Json() when json != null:
return json(_that);case RsHttpClientError_Io() when io != null:
return io(_that);case RsHttpClientError_Other() when other != null:
return other(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsHttpClientError_StatusCode value)  statusCode,required TResult Function( RsHttpClientError_Reqwest value)  reqwest,required TResult Function( RsHttpClientError_Json value)  json,required TResult Function( RsHttpClientError_Io value)  io,required TResult Function( RsHttpClientError_Other value)  other,}){
final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode():
return statusCode(_that);case RsHttpClientError_Reqwest():
return reqwest(_that);case RsHttpClientError_Json():
return json(_that);case RsHttpClientError_Io():
return io(_that);case RsHttpClientError_Other():
return other(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsHttpClientError_StatusCode value)?  statusCode,TResult? Function( RsHttpClientError_Reqwest value)?  reqwest,TResult? Function( RsHttpClientError_Json value)?  json,TResult? Function( RsHttpClientError_Io value)?  io,TResult? Function( RsHttpClientError_Other value)?  other,}){
final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that);case RsHttpClientError_Json() when json != null:
return json(_that);case RsHttpClientError_Io() when io != null:
return io(_that);case RsHttpClientError_Other() when other != null:
return other(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int status,  String? message)?  statusCode,TResult Function( String field0)?  reqwest,TResult Function( String field0)?  json,TResult Function( String field0)?  io,TResult Function( String field0)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that.status,_that.message);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that.field0);case RsHttpClientError_Json() when json != null:
return json(_that.field0);case RsHttpClientError_Io() when io != null:
return io(_that.field0);case RsHttpClientError_Other() when other != null:
return other(_that.field0);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int status,  String? message)  statusCode,required TResult Function( String field0)  reqwest,required TResult Function( String field0)  json,required TResult Function( String field0)  io,required TResult Function( String field0)  other,}) {final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode():
return statusCode(_that.status,_that.message);case RsHttpClientError_Reqwest():
return reqwest(_that.field0);case RsHttpClientError_Json():
return json(_that.field0);case RsHttpClientError_Io():
return io(_that.field0);case RsHttpClientError_Other():
return other(_that.field0);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int status,  String? message)?  statusCode,TResult? Function( String field0)?  reqwest,TResult? Function( String field0)?  json,TResult? Function( String field0)?  io,TResult? Function( String field0)?  other,}) {final _that = this;
switch (_that) {
case RsHttpClientError_StatusCode() when statusCode != null:
return statusCode(_that.status,_that.message);case RsHttpClientError_Reqwest() when reqwest != null:
return reqwest(_that.field0);case RsHttpClientError_Json() when json != null:
return json(_that.field0);case RsHttpClientError_Io() when io != null:
return io(_that.field0);case RsHttpClientError_Other() when other != null:
return other(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class RsHttpClientError_StatusCode extends RsHttpClientError {
  const RsHttpClientError_StatusCode({required this.status, this.message}): super._();
  

 final  int status;
 final  String? message;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_StatusCodeCopyWith<RsHttpClientError_StatusCode> get copyWith => _$RsHttpClientError_StatusCodeCopyWithImpl<RsHttpClientError_StatusCode>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_StatusCode&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode => Object.hash(runtimeType,status,message);

@override
String toString() {
  return 'RsHttpClientError.statusCode(status: $status, message: $message)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_StatusCodeCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_StatusCodeCopyWith(RsHttpClientError_StatusCode value, $Res Function(RsHttpClientError_StatusCode) _then) = _$RsHttpClientError_StatusCodeCopyWithImpl;
@useResult
$Res call({
 int status, String? message
});




}
/// @nodoc
class _$RsHttpClientError_StatusCodeCopyWithImpl<$Res>
    implements $RsHttpClientError_StatusCodeCopyWith<$Res> {
  _$RsHttpClientError_StatusCodeCopyWithImpl(this._self, this._then);

  final RsHttpClientError_StatusCode _self;
  final $Res Function(RsHttpClientError_StatusCode) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,Object? message = freezed,}) {
  return _then(RsHttpClientError_StatusCode(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as int,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class RsHttpClientError_Reqwest extends RsHttpClientError {
  const RsHttpClientError_Reqwest(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_ReqwestCopyWith<RsHttpClientError_Reqwest> get copyWith => _$RsHttpClientError_ReqwestCopyWithImpl<RsHttpClientError_Reqwest>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Reqwest&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.reqwest(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_ReqwestCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_ReqwestCopyWith(RsHttpClientError_Reqwest value, $Res Function(RsHttpClientError_Reqwest) _then) = _$RsHttpClientError_ReqwestCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_ReqwestCopyWithImpl<$Res>
    implements $RsHttpClientError_ReqwestCopyWith<$Res> {
  _$RsHttpClientError_ReqwestCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Reqwest _self;
  final $Res Function(RsHttpClientError_Reqwest) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Reqwest(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsHttpClientError_Json extends RsHttpClientError {
  const RsHttpClientError_Json(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_JsonCopyWith<RsHttpClientError_Json> get copyWith => _$RsHttpClientError_JsonCopyWithImpl<RsHttpClientError_Json>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Json&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.json(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_JsonCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_JsonCopyWith(RsHttpClientError_Json value, $Res Function(RsHttpClientError_Json) _then) = _$RsHttpClientError_JsonCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_JsonCopyWithImpl<$Res>
    implements $RsHttpClientError_JsonCopyWith<$Res> {
  _$RsHttpClientError_JsonCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Json _self;
  final $Res Function(RsHttpClientError_Json) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Json(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsHttpClientError_Io extends RsHttpClientError {
  const RsHttpClientError_Io(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_IoCopyWith<RsHttpClientError_Io> get copyWith => _$RsHttpClientError_IoCopyWithImpl<RsHttpClientError_Io>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Io&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.io(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_IoCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_IoCopyWith(RsHttpClientError_Io value, $Res Function(RsHttpClientError_Io) _then) = _$RsHttpClientError_IoCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_IoCopyWithImpl<$Res>
    implements $RsHttpClientError_IoCopyWith<$Res> {
  _$RsHttpClientError_IoCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Io _self;
  final $Res Function(RsHttpClientError_Io) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Io(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RsHttpClientError_Other extends RsHttpClientError {
  const RsHttpClientError_Other(this.field0): super._();
  

 final  String field0;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsHttpClientError_OtherCopyWith<RsHttpClientError_Other> get copyWith => _$RsHttpClientError_OtherCopyWithImpl<RsHttpClientError_Other>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsHttpClientError_Other&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'RsHttpClientError.other(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $RsHttpClientError_OtherCopyWith<$Res> implements $RsHttpClientErrorCopyWith<$Res> {
  factory $RsHttpClientError_OtherCopyWith(RsHttpClientError_Other value, $Res Function(RsHttpClientError_Other) _then) = _$RsHttpClientError_OtherCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$RsHttpClientError_OtherCopyWithImpl<$Res>
    implements $RsHttpClientError_OtherCopyWith<$Res> {
  _$RsHttpClientError_OtherCopyWithImpl(this._self, this._then);

  final RsHttpClientError_Other _self;
  final $Res Function(RsHttpClientError_Other) _then;

/// Create a copy of RsHttpClientError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(RsHttpClientError_Other(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RsUploadEvent {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsUploadEvent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RsUploadEvent()';
}


}

/// @nodoc
class $RsUploadEventCopyWith<$Res>  {
$RsUploadEventCopyWith(RsUploadEvent _, $Res Function(RsUploadEvent) __);
}


/// Adds pattern-matching-related methods to [RsUploadEvent].
extension RsUploadEventPatterns on RsUploadEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RsUploadEvent_Progress value)?  progress,TResult Function( RsUploadEvent_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that);case RsUploadEvent_Failed() when failed != null:
return failed(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RsUploadEvent_Progress value)  progress,required TResult Function( RsUploadEvent_Failed value)  failed,}){
final _that = this;
switch (_that) {
case RsUploadEvent_Progress():
return progress(_that);case RsUploadEvent_Failed():
return failed(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RsUploadEvent_Progress value)?  progress,TResult? Function( RsUploadEvent_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that);case RsUploadEvent_Failed() when failed != null:
return failed(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( double progress)?  progress,TResult Function( RsHttpClientError error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that.progress);case RsUploadEvent_Failed() when failed != null:
return failed(_that.error);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( double progress)  progress,required TResult Function( RsHttpClientError error)  failed,}) {final _that = this;
switch (_that) {
case RsUploadEvent_Progress():
return progress(_that.progress);case RsUploadEvent_Failed():
return failed(_that.error);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( double progress)?  progress,TResult? Function( RsHttpClientError error)?  failed,}) {final _that = this;
switch (_that) {
case RsUploadEvent_Progress() when progress != null:
return progress(_that.progress);case RsUploadEvent_Failed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class RsUploadEvent_Progress extends RsUploadEvent {
  const RsUploadEvent_Progress({required this.progress}): super._();
  

 final  double progress;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsUploadEvent_ProgressCopyWith<RsUploadEvent_Progress> get copyWith => _$RsUploadEvent_ProgressCopyWithImpl<RsUploadEvent_Progress>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsUploadEvent_Progress&&(identical(other.progress, progress) || other.progress == progress));
}


@override
int get hashCode => Object.hash(runtimeType,progress);

@override
String toString() {
  return 'RsUploadEvent.progress(progress: $progress)';
}


}

/// @nodoc
abstract mixin class $RsUploadEvent_ProgressCopyWith<$Res> implements $RsUploadEventCopyWith<$Res> {
  factory $RsUploadEvent_ProgressCopyWith(RsUploadEvent_Progress value, $Res Function(RsUploadEvent_Progress) _then) = _$RsUploadEvent_ProgressCopyWithImpl;
@useResult
$Res call({
 double progress
});




}
/// @nodoc
class _$RsUploadEvent_ProgressCopyWithImpl<$Res>
    implements $RsUploadEvent_ProgressCopyWith<$Res> {
  _$RsUploadEvent_ProgressCopyWithImpl(this._self, this._then);

  final RsUploadEvent_Progress _self;
  final $Res Function(RsUploadEvent_Progress) _then;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? progress = null,}) {
  return _then(RsUploadEvent_Progress(
progress: null == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

/// @nodoc


class RsUploadEvent_Failed extends RsUploadEvent {
  const RsUploadEvent_Failed({required this.error}): super._();
  

 final  RsHttpClientError error;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RsUploadEvent_FailedCopyWith<RsUploadEvent_Failed> get copyWith => _$RsUploadEvent_FailedCopyWithImpl<RsUploadEvent_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RsUploadEvent_Failed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode => Object.hash(runtimeType,error);

@override
String toString() {
  return 'RsUploadEvent.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $RsUploadEvent_FailedCopyWith<$Res> implements $RsUploadEventCopyWith<$Res> {
  factory $RsUploadEvent_FailedCopyWith(RsUploadEvent_Failed value, $Res Function(RsUploadEvent_Failed) _then) = _$RsUploadEvent_FailedCopyWithImpl;
@useResult
$Res call({
 RsHttpClientError error
});


$RsHttpClientErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$RsUploadEvent_FailedCopyWithImpl<$Res>
    implements $RsUploadEvent_FailedCopyWith<$Res> {
  _$RsUploadEvent_FailedCopyWithImpl(this._self, this._then);

  final RsUploadEvent_Failed _self;
  final $Res Function(RsUploadEvent_Failed) _then;

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(RsUploadEvent_Failed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as RsHttpClientError,
  ));
}

/// Create a copy of RsUploadEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RsHttpClientErrorCopyWith<$Res> get error {
  
  return $RsHttpClientErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on

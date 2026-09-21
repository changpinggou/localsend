import 'dart:typed_data';

import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust;
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:localsend_isolates/src/isolate/child/http_provider.dart';
import 'package:localsend_isolates/src/isolate/child/main.dart';
import 'package:localsend_isolates/src/isolate/dto/send_to_isolate_data.dart';
import 'package:typed_isolates/typed_isolates.dart';

/// T-009: parameters of a single remote filesystem download request.
class FsDownloadRequest {
  final Device device;
  final String path;
  final int? rangeStart;
  final int? rangeEnd;

  const FsDownloadRequest({
    required this.device,
    required this.path,
    this.rangeStart,
    this.rangeEnd,
  });
}

sealed class FsDownloadTask {}

class FsDownloadStartTask implements FsDownloadTask {
  final FsDownloadRequest request;
  final String sessionId;

  FsDownloadStartTask(this.request, this.sessionId);
}

sealed class FsDownloadResult {}

class FsDownloadStartedResult implements FsDownloadResult {
  final int totalSize;
  final int status;
  FsDownloadStartedResult({required this.totalSize, required this.status});
}

class FsDownloadChunkResult implements FsDownloadResult {
  final Uint8List bytes;
  final int transferred;
  FsDownloadChunkResult({required this.bytes, required this.transferred});
}

class FsDownloadFinishedResult implements FsDownloadResult {
  final int totalTransferred;
  FsDownloadFinishedResult(this.totalTransferred);
}

class FsDownloadCancelledResult implements FsDownloadResult {
  FsDownloadCancelledResult();
}

class FsDownloadFailedResult implements FsDownloadResult {
  final String message;
  FsDownloadFailedResult(this.message);
}

/// T-009: child isolate entry point.
///
/// Spawned by [ParentIsolateState.fsDownload]. The isolate holds one
/// pending download at a time (the cancel token from the previous one
/// is cancelled when a new start task arrives). It then opens an FRB
/// `StreamSink<RsFsDownloadEvent>` against the pinned HTTP client and
/// converts each event into a typed [FsDownloadResult] for the parent.
Future<void> setupFsDownloadIsolate(
  Stream<SendToIsolateData<IsolateTask<FsDownloadTask>>> receiveFromMain,
  void Function(IsolateTaskStreamResult<FsDownloadResult>) sendToMain,
  InitialData initialData,
) async {
  await setupChildIsolateHelper(
    debugLabel: 'FsDownloadIsolate',
    receiveFromMain: receiveFromMain,
    sendToMain: sendToMain,
    initialData: initialData,
    handler: (ref, task) async {
      switch (task.data) {
        case FsDownloadStartTask(:final request, :final sessionId):
          final client = ref.read(httpProvider).pinnedTo(request.device.fingerprint);
          final device = request.device;
          final protocol = device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http;
          final ip = device.ip;
          if (ip == null) {
            sendToMain(
              IsolateTaskStreamResult.event(
                id: task.id,
                data: FsDownloadFailedResult('Device has no IP address (signaling-only)'),
              ),
            );
            return;
          }

          final cancelToken = createCancellationToken();
          _pendingCancelTokens[sessionId]?.cancel();
          _pendingCancelTokens[sessionId] = cancelToken;

          final stream = client.fsDownload(
            protocol: protocol,
            ip: ip,
            port: device.port,
            path: request.path,
            rangeStart: request.rangeStart == null ? null : BigInt.from(request.rangeStart!),
            rangeEnd: request.rangeEnd == null ? null : BigInt.from(request.rangeEnd!),
            cancelToken: cancelToken,
          );

          await for (final event in stream) {
            final FsDownloadResult result;
            if (event is rust.RsFsDownloadEvent_Started) {
              result = FsDownloadStartedResult(
                totalSize: event.totalSize.toInt(),
                status: event.status,
              );
            } else if (event is rust.RsFsDownloadEvent_Chunk) {
              result = FsDownloadChunkResult(
                bytes: event.bytes,
                transferred: event.transferred.toInt(),
              );
              _lastTransferred = event.transferred.toInt();
            } else if (event is rust.RsFsDownloadEvent_Finished) {
              result = FsDownloadFinishedResult(_lastTransferred);
            } else if (event is rust.RsFsDownloadEvent_Cancelled) {
              result = FsDownloadCancelledResult();
            } else if (event is rust.RsFsDownloadEvent_Failed) {
              result = FsDownloadFailedResult(event.error.toString());
            } else {
              continue;
            }
            sendToMain(
              IsolateTaskStreamResult.event(
                id: task.id,
                data: result,
              ),
            );
          }

          _pendingCancelTokens.remove(sessionId);
          sendToMain(
            IsolateTaskStreamResult.done(id: task.id),
          );
      }
    },
  );
}

final Map<String, RsCancellationToken> _pendingCancelTokens = {};
int _lastTransferred = 0;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/cancel.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust;
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:localsend_isolates/rust/api/stream.dart';
import 'package:localsend_isolates/src/isolate/child/http_provider.dart';
import 'package:localsend_isolates/src/isolate/child/main.dart';
import 'package:localsend_isolates/src/isolate/dto/send_to_isolate_data.dart';
import 'package:typed_isolates/typed_isolates.dart';

/// T-012: parameters of a single remote filesystem upload request.
class FsUploadRequest {
  final Device device;
  final String localPath;
  final String remotePath;

  /// Filename the file gets on the peer. Callers pass this explicitly
  /// because `basename(localPath)` is not always the intended name —
  /// on iOS, `asset.originFile.path` is a mangled tmp path that has
  /// nothing to do with the photo-library title.
  final String filename;

  const FsUploadRequest({
    required this.device,
    required this.localPath,
    required this.remotePath,
    required this.filename,
  });
}

sealed class FsUploadTask {}

class FsUploadStartTask implements FsUploadTask {
  final FsUploadRequest request;
  final String sessionId;

  FsUploadStartTask(this.request, this.sessionId);
}

class FsUploadCancelTask implements FsUploadTask {
  final String sessionId;

  FsUploadCancelTask(this.sessionId);
}

sealed class FsUploadResult {}

class FsUploadProgressEvent implements FsUploadResult {
  final int transferred;
  FsUploadProgressEvent({required this.transferred});
}

class FsUploadFinishedEvent implements FsUploadResult {
  FsUploadFinishedEvent();
}

class FsUploadCancelledEvent implements FsUploadResult {
  FsUploadCancelledEvent();
}

class FsUploadFailedEvent implements FsUploadResult {
  final String error;
  FsUploadFailedEvent(this.error);
}

/// T-012: child isolate entry point for file uploads.
///
/// Spawned by [ParentIsolateState.fsUpload]. The isolate holds a map of
/// pending uploads keyed by session ID. Each upload streams file bytes
/// to the Rust layer, which handles the HTTP chunked transfer.
Future<void> setupFsUploadIsolate(
  Stream<SendToIsolateData<IsolateTask<FsUploadTask>>> receiveFromMain,
  void Function(IsolateTaskStreamResult<FsUploadResult>) sendToMain,
  InitialData initialData,
) async {
  await setupChildIsolateHelper(
    debugLabel: 'FsUploadIsolate',
    receiveFromMain: receiveFromMain,
    sendToMain: sendToMain,
    initialData: initialData,
    handler: (ref, task) async {
      switch (task.data) {
        case FsUploadStartTask(:final request, :final sessionId):
          final client = ref.read(httpProvider).pinnedTo(request.device.fingerprint);
          final device = request.device;
          final protocol = device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http;
          final ip = device.ip;
          if (ip == null) {
            sendToMain(
              IsolateTaskStreamResult.event(
                id: task.id,
                data: FsUploadFailedEvent('Device has no IP address (signaling-only)'),
              ),
            );
            sendToMain(
              IsolateTaskStreamResult.done(id: task.id),
            );
            return;
          }

          final cancelToken = createCancellationToken();
          _pendingCancelTokens[sessionId]?.cancel();
          _pendingCancelTokens[sessionId] = cancelToken;

          // Read the file in chunks and stream to Rust
          final file = File(request.localPath);
          if (!await file.exists()) {
            sendToMain(
              IsolateTaskStreamResult.event(
                id: task.id,
                data: FsUploadFailedEvent('File does not exist: ${request.localPath}'),
              ),
            );
            sendToMain(
              IsolateTaskStreamResult.done(id: task.id),
            );
            return;
          }

          final fileSize = await file.length();

          try {
            // Create FRB stream pair for sending bytes to Rust
            final (streamSink, streamReceiver) = await createStream();

            // Start the upload in the background
            final uploadStream = client.fsUpload(
              protocol: protocol,
              ip: ip,
              port: device.port,
              remoteDir: request.remotePath,
              filename: request.filename,
              fileSize: BigInt.from(fileSize),
              binary: streamReceiver,
              resumeSessionId: null, // TODO: implement resume
              resumeEtag: null,
              resumeOffset: null,
              cancelToken: cancelToken,
            );

            // Listen to upload events from Rust
            final uploadCompleter = Completer<void>();
            var uploadCancelled = false;
            uploadStream.listen(
              (event) {
                if (event is rust.RsFsUploadEvent_Started) {
                  // Session initialized, we can start sending chunks
                } else if (event is rust.RsFsUploadEvent_Progress) {
                  // Update progress
                  sendToMain(
                    IsolateTaskStreamResult.event(
                      id: task.id,
                      data: FsUploadProgressEvent(transferred: event.sent.toInt()),
                    ),
                  );
                } else if (event is rust.RsFsUploadEvent_Finished) {
                  // Upload completed
                  sendToMain(
                    IsolateTaskStreamResult.event(
                      id: task.id,
                      data: FsUploadFinishedEvent(),
                    ),
                  );
                  if (!uploadCompleter.isCompleted) uploadCompleter.complete();
                } else if (event is rust.RsFsUploadEvent_Cancelled) {
                  // Upload cancelled
                  uploadCancelled = true;
                  sendToMain(
                    IsolateTaskStreamResult.event(
                      id: task.id,
                      data: FsUploadCancelledEvent(),
                    ),
                  );
                  if (!uploadCompleter.isCompleted) uploadCompleter.complete();
                } else if (event is rust.RsFsUploadEvent_Failed) {
                  // Upload failed
                  sendToMain(
                    IsolateTaskStreamResult.event(
                      id: task.id,
                      data: FsUploadFailedEvent(event.error.toString()),
                    ),
                  );
                  if (!uploadCompleter.isCompleted) uploadCompleter.complete();
                }
              },
              onError: (error) {
                sendToMain(
                  IsolateTaskStreamResult.event(
                    id: task.id,
                    data: FsUploadFailedEvent(error.toString()),
                  ),
                );
                if (!uploadCompleter.isCompleted) uploadCompleter.complete();
              },
            );

            // Open file and send chunks to Rust via streamSink
            final fileStream = file.openRead();
            await for (final chunk in fileStream) {
              if (uploadCancelled) {
                break;
              }
              // Convert List<int> to Uint8List
              final bytes = Uint8List.fromList(chunk);
              await streamSink.add(data: bytes);
            }

            // Close the stream to signal end of data
            streamSink.close();
            await uploadCompleter.future;
          } catch (e) {
            sendToMain(
              IsolateTaskStreamResult.event(
                id: task.id,
                data: FsUploadFailedEvent(e.toString()),
              ),
            );
          }

          _pendingCancelTokens.remove(sessionId);
          sendToMain(
            IsolateTaskStreamResult.done(id: task.id),
          );

        case FsUploadCancelTask(:final sessionId):
          _pendingCancelTokens[sessionId]?.cancel();
          _pendingCancelTokens.remove(sessionId);
          sendToMain(
            IsolateTaskStreamResult.done(id: task.id),
          );
      }
    },
  );
}

/// Pending cancel tokens keyed by session ID.
final Map<String, RsCancellationToken> _pendingCancelTokens = {};

import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/http.dart' as rust;
import 'package:localsend_isolates/rust/api/model.dart' as rust_model;
import 'package:localsend_isolates/src/isolate/child/http_provider.dart';
import 'package:localsend_isolates/src/isolate/child/main.dart';
import 'package:localsend_isolates/src/isolate/dto/send_to_isolate_data.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:typed_isolates/typed_isolates.dart';

sealed class FsListTask {}

final _logger = Logger('FsListIsolate');

/// One request to the remote filesystem (T-008).
///
/// For the roots level (where [FsListRequest.path] is empty), the isolate
/// calls `GET /api/localsend/v2/fs/roots` and returns the list of mount
/// points. For any other [FsListRequest.path], it calls
/// `GET /api/localsend/v2/fs/list` and returns a paginated directory
/// listing.
class FsListRequest {
  final Device device;
  final String path;
  final int page;
  final int size;
  final String sort;

  const FsListRequest({
    required this.device,
    required this.path,
    required this.page,
    required this.size,
    required this.sort,
  });
}

class FsListRootsTask implements FsListTask {
  final FsListRequest request;

  FsListRootsTask(this.request);
}

class FsListDirTask implements FsListTask {
  final FsListRequest request;

  FsListDirTask(this.request);
}

/// A response from the fs list isolate.
sealed class FsListResult {}

class FsListRootsResult implements FsListResult {
  final List<rust_model.FsRoot> roots;

  FsListRootsResult(this.roots);
}

class FsListDirResult implements FsListResult {
  final List<rust_model.FsEntry> entries;
  final BigInt total;
  final bool hasMore;

  FsListDirResult({
    required this.entries,
    required this.total,
    required this.hasMore,
  });
}

/// T-008 follow-up: surfaces HTTP / TLS / parse errors so the UI
/// can stop showing the loading skeleton and fall back to
/// [FsErrorState]. Without this, the isolate handler would let the
/// exception bubble up to `setupChildIsolateHelper` which logs it
/// but never tells the page — leaving the user staring at a
/// spinner until they give up.
class FsListFailedResult implements FsListResult {
  final String message;
  FsListFailedResult(this.message);
}

Future<void> setupFsListIsolate(
  Stream<SendToIsolateData<IsolateTask<FsListTask>>> receiveFromMain,
  void Function(IsolateTaskStreamResult<FsListResult>) sendToMain,
  InitialData initialData,
) async {
  await setupChildIsolateHelper(
    debugLabel: 'FsListIsolate',
    receiveFromMain: receiveFromMain,
    sendToMain: sendToMain,
    initialData: initialData,
    handler: (ref, task) async {
      final FsListRequest request = switch (task.data) {
        FsListRootsTask(:final request) => request,
        FsListDirTask(:final request) => request,
      };

      // Pinned to the device the user picked, so the request is not sent at
      // all if someone else answers on that address.
      final client = ref.read(httpProvider).pinnedTo(request.device.fingerprint);

      final device = request.device;
      final protocol = device.https ? rust_model.ProtocolType.https : rust_model.ProtocolType.http;
      final ip = device.ip;

      if (ip == null) {
        throw StateError('Cannot list files of a device without an IP (signaling-only device)');
      }

      if (request.path.isEmpty) {
        // T-008 follow-up: log the actual host:port we're hitting so a
        // real-device verifier can tell 'we reached the Windows host'
        // from 'we ended up on the same Mac (404 from the older
        // isolates crate that didn't have the fs feature on)'.
        _logger.info(
          'fs_list_roots -> $protocol://$ip:${device.port}/api/localsend/v2/fs/roots '
          '(device fingerprint ${device.fingerprint.substring(0, 16)}...)',
        );
        try {
          final roots = await client.listRoots(
            protocol: protocol,
            ip: ip,
            port: device.port,
          );
          sendToMain(
            IsolateTaskStreamResult.event(
              id: task.id,
              data: FsListRootsResult(roots.roots),
            ),
          );
        } catch (e, st) {
          _logger.warning('Failed to list fs roots', e, st);
          sendToMain(
            IsolateTaskStreamResult.event(
              id: task.id,
              data: FsListFailedResult(e.toString()),
            ),
          );
        }
      } else {
        try {
          final response = await client.listDir(
            protocol: protocol,
            ip: ip,
            port: device.port,
            path: request.path,
            page: request.page,
            size: request.size,
            sort: request.sort,
          );
          sendToMain(
            IsolateTaskStreamResult.event(
              id: task.id,
              data: FsListDirResult(
                entries: response.entries,
                total: response.total,
                hasMore: response.hasMore,
              ),
            ),
          );
        } catch (e, st) {
          _logger.warning('Failed to list fs path=${request.path}', e, st);
          sendToMain(
            IsolateTaskStreamResult.event(
              id: task.id,
              data: FsListFailedResult(e.toString()),
            ),
          );
        }
      }


      sendToMain(
        IsolateTaskStreamResult.done(
          id: task.id,
        ),
      );
    },
  );
}

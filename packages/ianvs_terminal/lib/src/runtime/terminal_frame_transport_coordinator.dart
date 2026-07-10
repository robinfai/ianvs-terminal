import 'dart:typed_data';

import 'package:ianvs_pty/ianvs_pty.dart';

import 'terminal_backend_request_error.dart';
import 'terminal_frame_decoder.dart';

enum TerminalFrameWireFormatPreference { automatic, json }

final class TerminalFrameTransportCoordinator {
  TerminalFrameTransportCoordinator({
    required PtySessionBackend backend,
    required TerminalFrameDecoder decoder,
    required TerminalFrameWireFormatPreference preference,
    TerminalBackendRequestErrorHandler? onRequestError,
  }) : _backend = backend,
       _decoder = decoder,
       _preference = preference,
       _onRequestError = onRequestError;

  final PtySessionBackend _backend;
  final TerminalFrameDecoder _decoder;
  final TerminalFrameWireFormatPreference _preference;
  final TerminalBackendRequestErrorHandler? _onRequestError;

  TerminalDecodedFrame? take(String sessionId) {
    if (_preference == TerminalFrameWireFormatPreference.json) {
      return _takeJson(sessionId);
    }

    final backend = _backend;
    final protobufBackend = backend is PtySessionProtobufFrameBackend
        ? backend as PtySessionProtobufFrameBackend
        : null;
    if (protobufBackend != null && protobufBackend.supportsProtobufFrameDiffs) {
      return _takeProtobuf(sessionId, protobufBackend);
    }
    return _takeJson(sessionId);
  }

  TerminalDecodedFrame? _takeJson(String sessionId) {
    final String? rawFrame;
    try {
      rawFrame = _backend.takeFrameDiffJson(sessionId);
    } on Object catch (error, stackTrace) {
      _onRequestError?.call(sessionId, 'takeFrameDiffJson', error, stackTrace);
      return null;
    }
    if (rawFrame == null || rawFrame.isEmpty) {
      return null;
    }
    return _decoder.decodeJson(rawFrame);
  }

  TerminalDecodedFrame? _takeProtobuf(
    String sessionId,
    PtySessionProtobufFrameBackend backend,
  ) {
    final Uint8List? rawFrame;
    try {
      rawFrame = backend.takeFrameDiffProtobuf(sessionId);
    } on Object catch (error, stackTrace) {
      _onRequestError?.call(
        sessionId,
        'takeFrameDiffProtobuf',
        error,
        stackTrace,
      );
      return null;
    }
    if (rawFrame == null || rawFrame.isEmpty) {
      return null;
    }
    return _decoder.decodeProtobuf(rawFrame);
  }
}

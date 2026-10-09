import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import '../core/services/nfc_servide.dart';

class NativeNfcService implements NfcService {
  Completer<String?>? _scanResult;
  Completer<bool>? _writeResult;
  Timer? _timeout;

  @override
  Future<bool> isAvailable() async => await NfcManager.instance.checkAvailability() == NfcAvailability.enabled;

  @override
  Future<String?> scan() async {
    await cancel();
    final result = _scanResult = Completer<String?>();
    await NfcManager.instance.startSession(
      pollingOptions: const {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      alertMessageIos: 'Hold your phone near a Tapat AI NFC tag.',
      onDiscovered: (tag) async {
        final id = parseTopicId(Ndef.from(tag)?.cachedMessage);
        _timeout?.cancel();
        _timeout = null;
        _scanResult = null;
        await NfcManager.instance.stopSession();
        if (!result.isCompleted) result.complete(id);
      },
      onSessionErrorIos: (error) {
        if (!result.isCompleted) result.completeError(StateError(error.message));
      },
    );
    _timeout = Timer(const Duration(seconds: 45), () async {
      await cancel();
      if (!result.isCompleted) result.complete(null);
    });
    return result.future;
  }

  @override
  Future<bool> write(String payload) async {
    await cancel();
    final result = _writeResult = Completer<bool>();
    final uri = Uri.tryParse(payload);
    final uuid = uri?.scheme == 'tapat' && uri?.host == 'kb' ? uri?.pathSegments.firstOrNull : null;
    if (uuid == null || uuid.isEmpty) throw const FormatException('Invalid Tapat topic NFC link.');
    final message = _message(uuid);
    await NfcManager.instance.startSession(
      pollingOptions: const {NfcPollingOption.iso14443},
      alertMessageIos: 'Hold a writable NFC tag near your phone.',
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            final formatable = defaultTargetPlatform == TargetPlatform.android
                ? NdefFormatableAndroid.from(tag) : null;
            if (formatable == null) throw StateError('This tag is not NDEF-compatible or cannot be formatted on this device.');
            if (message.byteLength > 512) throw StateError('This message is too large for a blank tag.');
            await formatable.format(message);
            await NfcManager.instance.stopSession();
            await _verifyAfterFormat(uuid, result);
            return;
          }
          if (!ndef.isWritable) throw StateError('This NFC tag is read-only.');
          if (message.byteLength > ndef.maxSize) throw StateError('This NFC tag does not have enough capacity.');
          await ndef.write(message: message);
          final readBack = await ndef.read();
          if (parseTopicId(readBack) != uuid) throw StateError('The NFC tag write could not be verified.');
          _timeout?.cancel();
          _timeout = null;
          _writeResult = null;
          await NfcManager.instance.stopSession(alertMessageIos: 'Tag linked successfully.');
          if (!result.isCompleted) result.complete(true);
        } catch (e) {
          await NfcManager.instance.stopSession(errorMessageIos: e.toString());
          if (!result.isCompleted) result.completeError(e);
        }
      },
      onSessionErrorIos: (error) {
        if (!result.isCompleted) result.completeError(StateError(error.message));
      },
    );
    _timeout = Timer(const Duration(seconds: 45), () async {
      await cancel();
      if (!result.isCompleted) result.completeError(TimeoutException('No NFC tag was detected.'));
    });
    return result.future;
  }

  @override
  Future<bool> erase() async {
    await cancel();
    final result = _writeResult = Completer<bool>();
    await NfcManager.instance.startSession(
      pollingOptions: const {NfcPollingOption.iso14443},
      alertMessageIos: 'Hold a writable NFC tag near your phone to erase it.',
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) {
            final formatable = defaultTargetPlatform == TargetPlatform.android
                ? NdefFormatableAndroid.from(tag) : null;
            if (formatable == null) throw StateError('This tag cannot be formatted on this device.');
            await formatable.format(NdefMessage(records: const []));
          } else {
            if (!ndef.isWritable) throw StateError('This NFC tag is read-only.');
            await ndef.write(message: NdefMessage(records: const []));
            final readBack = await ndef.read();
            if (readBack == null || readBack.records.isNotEmpty) {
              throw StateError('The NFC tag could not be verified as empty.');
            }
          }
          _timeout?.cancel();
          _timeout = null;
          _writeResult = null;
          await NfcManager.instance.stopSession(alertMessageIos: 'Tag erased.');
          if (!result.isCompleted) result.complete(true);
        } catch (e) {
          await NfcManager.instance.stopSession(errorMessageIos: e.toString());
          if (!result.isCompleted) result.completeError(e);
        }
      },
      onSessionErrorIos: (error) {
        if (!result.isCompleted) result.completeError(StateError(error.message));
      },
    );
    _timeout = Timer(const Duration(seconds: 45), () async {
      await cancel();
      if (!result.isCompleted) result.completeError(TimeoutException('No NFC tag was detected.'));
    });
    return result.future;
  }

  Future<void> _verifyAfterFormat(String uuid, Completer<bool> result) async {
    await NfcManager.instance.startSession(
      pollingOptions: const {NfcPollingOption.iso14443},
      alertMessageIos: 'Re-tap the tag to verify it.',
      onDiscovered: (tag) async {
        final message = await Ndef.from(tag)?.read();
        final valid = parseTopicId(message) == uuid;
        await NfcManager.instance.stopSession(alertMessageIos: valid ? 'Tag linked successfully.' : null);
        if (!result.isCompleted) {
          valid ? result.complete(true) : result.completeError(StateError('The NFC tag write could not be verified.'));
        }
      },
      onSessionErrorIos: (error) {
        if (!result.isCompleted) result.completeError(StateError(error.message));
      },
    );
  }

  static NdefMessage _message(String uuid) => NdefMessage(records: [
    NdefRecord(typeNameFormat: TypeNameFormat.wellKnown, type: Uint8List.fromList([0x55]),
      identifier: Uint8List(0), payload: Uint8List.fromList([0, ...utf8.encode('tapat://kb/$uuid')])),
    NdefRecord(typeNameFormat: TypeNameFormat.external, type: Uint8List.fromList(utf8.encode('tapat.ai:topic')),
      identifier: Uint8List(0), payload: Uint8List.fromList(utf8.encode(uuid))),
  ]);

  static String? parseTopicId(NdefMessage? message) {
    if (message == null) return null;
    for (final record in message.records) {
      if (record.typeNameFormat == TypeNameFormat.external && utf8.decode(record.type, allowMalformed: true) == 'tapat.ai:topic') {
        final id = utf8.decode(record.payload, allowMalformed: true).trim();
        if (id.isNotEmpty) return id;
      }
      if (record.typeNameFormat == TypeNameFormat.wellKnown && record.type.length == 1 && record.type.first == 0x55 && record.payload.length > 1) {
        final uri = Uri.tryParse(utf8.decode(record.payload.sublist(1), allowMalformed: true));
        if (uri?.scheme == 'tapat' && uri?.host == 'kb' && uri!.pathSegments.isNotEmpty) return uri.pathSegments.first;
      }
    }
    return null;
  }

  @override
  Future<void> cancel() async {
    _timeout?.cancel();
    _timeout = null;
    final scan = _scanResult;
    if (scan != null && !scan.isCompleted) scan.complete(null);
    _scanResult = null;
    final write = _writeResult;
    if (write != null && !write.isCompleted) write.complete(false);
    _writeResult = null;
    try { await NfcManager.instance.stopSession(); } catch (_) { /* no session active */ }
  }
}

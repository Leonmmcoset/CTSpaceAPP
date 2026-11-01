import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'models.dart';

String solveProofOfWork(Json input) {
  final challenge = textOf(input['challenge']);
  final difficulty = intOf(input['difficulty']);
  if (challenge.isEmpty || difficulty < 0 || difficulty > 6) {
    throw const ApiFailure('验证码异常，请刷新');
  }
  final prefix = '0' * difficulty;
  for (var nonce = 0; ; nonce++) {
    final hash = sha256.convert(utf8.encode('$challenge:$nonce')).toString();
    if (hash.startsWith(prefix)) return '$nonce';
  }
}

Future<String> computeProofOfWork(Json challenge) =>
    compute(solveProofOfWork, challenge);

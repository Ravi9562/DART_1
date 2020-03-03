// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:gcloud/db.dart';
import 'package:retry/retry.dart';
import 'package:logging/logging.dart';
import 'exceptions.dart';

final Logger _logger = Logger('pub.datastore_helper');

/// Wrap [Transaction] to avoid exposing [Transaction.commit] and
/// [Transaction.rollback].
class TransactionWrapper {
  final Transaction _tx;
  bool _mutated = false;

  TransactionWrapper._(this._tx);

  /// See [Transaction.lookup].
  Future<List<T>> lookup<T extends Model>(List<Key> keys) =>
      _tx.lookup<T>(keys);

  /// [lookupValue] or return `null`.
  Future<T> lookupOrNull<T extends Model>(Key key) =>
      _tx.lookupValue<T>(key, orElse: () => null);

  /// See [Transaction.lookupValue].
  Future<T> lookupValue<T extends Model>(Key key, {T Function() orElse}) =>
      _tx.lookupValue<T>(key, orElse: orElse);

  /// See [Transaction.query].
  Query<T> query<T extends Model>(Key ancestorKey, {Partition partition}) =>
      _tx.query<T>(ancestorKey, partition: partition);

  /// Insert [entity] in this transaction.
  void insert(Model entity) => queueMutations(inserts: [entity]);

  /// Delete entity at [key] in this transaction.
  void delete(Key key) => queueMutations(deletes: [key]);

  /// See [Transaction.queueMutations].
  void queueMutations({List<Model> inserts, List<Key> deletes}) {
    _mutated = true;
    _tx.queueMutations(inserts: inserts, deletes: deletes);
  }
}

/// Call [fn] with a [TransactionWrapper] that is either committed or
/// rolled back when [fn] returns.
Future<T> withTransaction<T>(
  DatastoreDB db,
  Future<T> Function(TransactionWrapper tx) fn,
) async {
  return db.withTransaction<T>((tx) async {
    bool done = false;
    try {
      final wrapper = TransactionWrapper._(tx);
      final retval = await fn(wrapper);
      if (wrapper._mutated) {
        await tx.commit();
        done = true;
      }
      return retval;
    } catch (e, st) {
      _logger.info('Observed exception inside transaction block.', e, st);
      rethrow;
    } finally {
      if (!done) {
        await tx.rollback();
      }
    }
  });
}

/// Transaction retry options.
///
/// Transactions should be retried within the 30s timeout for sending an inital
/// response header on AppEngine Flexible. We suspect that AppEngine Flexible
/// has such a timeout, because it uses GCP HTTPS load-balancer under the hood.
///
/// When we would prefer to finish in 30s, and, thus, lower the delays between
/// retries to ensure that:
/// * 0th attempt is delayed    0 ms, with max accumulated delay     0 ms.
/// * 1st attempt is delayed  100 ms, with max accumulated delay   125 ms.
/// * 2nd attempt is delayed  200 ms, with max accumulated delay   375 ms.
/// * 3rd attempt is delayed  400 ms, with max accumulated delay   875 ms.
/// * 4th attempt is delayed  800 ms, with max accumulated delay  1875 ms.
/// * 5th attempt is delayed 1600 ms, with max accumulated delay  3875 ms.
/// * 6th attempt is delayed 3200 ms, with max accumulated delay  7875 ms.
/// * 7th attempt is delayed 5000 ms, with max accumulated delay 14125 ms.
final _transactionRetrier = RetryOptions(
  maxAttempts: 8,
  delayFactor: Duration(milliseconds: 20),
  maxDelay: Duration(seconds: 5),
  randomizationFactor: 0.25,
);

/// Call [fn] with a [TransactionWrapper] that is either committed or
/// rolled back when [fn] returns, and retried if [fn] fails.
///
/// This does not retry [ResponseException].
Future<T> withRetryTransaction<T>(
  DatastoreDB db,
  Future<T> Function(TransactionWrapper tx) fn,
) =>
    _transactionRetrier.retry<T>(
      () => withTransaction<T>(db, fn),
      // Never retry a ResponseException
      retryIf: (e) => e is! ResponseException,
      onRetry: (e) => _logger.info('retrying transaction', e),
    );

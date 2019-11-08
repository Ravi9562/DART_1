// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:appengine/appengine.dart';
import 'package:args/args.dart';
import 'package:gcloud/db.dart';
import 'package:pool/pool.dart';
import 'package:pub_dev/package/models.dart';
import 'package:pub_dev/service/entrypoint/tools.dart';

final _argParser = ArgParser()
  ..addOption('concurrency',
      abbr: 'c', defaultsTo: '10', help: 'Number of concurrent processing.')
  ..addFlag('help', abbr: 'h', defaultsTo: false, help: 'Show help.');

Future main(List<String> args) async {
  final argv = _argParser.parse(args);
  if (argv['help'] as bool == true) {
    print('Usage: dart backfill_packagelikes.dart');
    print('Ensures Package.likes is set to an integer.');
    print(_argParser.usage);
    return;
  }

  final concurrency = int.parse(argv['concurrency'] as String);

  await withProdServices(() async {
    final pool = Pool(concurrency);
    final futures = <Future>[];

    useLoggingPackageAdaptor();
    await for (Package p in dbService.query<Package>().run()) {
      final f = pool.withResource(() => _backfillPackageLikes(p));
      futures.add(f);
    }

    await Future.wait(futures);
    await pool.close();
  });
}

Future<void> _backfillPackageLikes(Package p) async {
  if (p.likes != null) return;
  print('Backfilling like property on package ${p.name}');
  try {
    await dbService.withTransaction((Transaction tx) async {
      final package = await tx.lookupValue<Package>(p.key, orElse: () => null);
      if (package == null) {
        return;
      }
      package.likes = 0;
      tx.queueMutations(inserts: [package]);
      await tx.commit();
      print('Updated likes property on package ${package.name}.');
    });
  } catch (e) {
    print('Failed to update likes on package ${p.name}, error $e');
  }
}

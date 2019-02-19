// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:gcloud/db.dart';

import 'package:pub_dartlang_org/account/backend.dart';
import 'package:pub_dartlang_org/account/models.dart';
import 'package:pub_dartlang_org/frontend/service_utils.dart';

Future main(List<String> args) async {
  int count = 0;
  await withProdServices(() async {
    registerAccountBackend(AccountBackend(dbService));

    final query = dbService.query<User>();
    await for (User user in query.run()) {
      count++;
      if (count % 100 == 0) {
        print(count);
      }
      if (user.email != user.email.toLowerCase()) {
        print('BAD: ${user.userId} ${user.email}');
      }
    }

    print('$count User entity checked.');
  });
}

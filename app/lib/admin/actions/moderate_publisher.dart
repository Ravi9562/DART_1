// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_dev/publisher/backend.dart';
import 'package:pub_dev/publisher/models.dart';
import 'package:pub_dev/shared/datastore.dart';

import 'actions.dart';

final moderatePublisher = AdminAction(
  name: 'moderate-publisher',
  summary:
      'Set the moderated flag on a publisher (making it invisible and unable to change).',
  description: '''
Set the moderated flag on a publisher (updating the flag and the timestamp). The
moderated package page page says it is moderated, packages owned by publisher
can't be updated, administrators must not be able to update publisher options.
''',
  options: {
    'publisher': 'The publisherId to be moderated',
    'state':
        'Set moderated state true / false. Returns current state if omitted.',
  },
  invoke: (options) async {
    final publisherId = options['publisher'];
    InvalidInputException.check(
      publisherId != null && publisherId.isNotEmpty,
      'publisherId must be given',
    );

    final publisher = await publisherBackend.getPublisher(publisherId!);
    InvalidInputException.check(
        publisher != null, 'Unable to locate publisher.');

    final state = options['state'];
    bool? valueToSet;
    switch (state) {
      case 'true':
        valueToSet = true;
        break;
      case 'false':
        valueToSet = false;
        break;
    }

    Publisher? publisher2;
    if (valueToSet != null) {
      publisher2 = await withRetryTransaction(dbService, (tx) async {
        final p = await tx.lookupValue<Publisher>(publisher!.key);
        p.updateIsModerated(isModerated: valueToSet!);
        tx.insert(p);
        return p;
      });
      await purgePublisherCache(publisherId: publisherId);
    }

    return {
      'publisherId': publisher!.publisherId,
      'before': {
        'isModerated': publisher.isModerated,
        'moderatedAt': publisher.moderatedAt?.toIso8601String(),
      },
      if (publisher2 != null)
        'after': {
          'isModerated': publisher2.isModerated,
          'moderatedAt': publisher2.moderatedAt?.toIso8601String(),
        },
    };
  },
);

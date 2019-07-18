// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:test/test.dart';

import '../../shared/handlers_test_utils.dart';
import '../../shared/test_services.dart';

import '_utils.dart';

void main() {
  group('publisher handlers tests', () {
    // TODO: add test for /create-publisher page
    // TODO: add test for POST /api/publisher/<publisherId> API calls
    // TODO: add test for GET /api/publisher/<publisherId> API calls

    group('PUT /api/publisher/<publisherId>', () {
      testWithServices('No active user', () async {
        final rs = await httpRequest(
          'PUT',
          '/api/publisher/example.com',
          jsonBody: {
            'description': 'new description',
          },
        );
        await expectJsonResponse(
          rs,
          status: 401,
          body: {
            'message':
                'Unauthorized access: try `pub logout` to re-initialize your login session.'
          },
        );
      });
    });

    // TODO: add test for POST /api/publisher/<publisherId>/invite-member API calls
    // TODO: add test for GET /api/publisher/<publisherId>/members API calls
    // TODO: add test for GET /api/publisher/<publisherId>/members/<userId> API calls
    // TODO: add test for PUT /api/publisher/<publisherId>/members/<userId> API calls
    // TODO: add test for DELETE /api/publisher/<publisherId>/members/<userId> API calls
  });
}

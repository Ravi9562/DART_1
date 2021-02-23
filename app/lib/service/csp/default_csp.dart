// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

final _none = <String>["'none'"];

final defaultContentSecurityPolicyMap = <String, List<String>>{
  'default-src': <String>[
    "'self'",
    'https:',
  ],
  'font-src': <String>[
    "'self'",
    'data:',
    'https://fonts.googleapis.com/',
    'https://fonts.gstatic.com/',
  ],
  'img-src': <String>[
    "'self'",
    'https:',
    'data:',
  ],
  'manifest-src': _none,
  'object-src': _none,
  'script-src': <String>[
    // See: https://developers.google.com/tag-manager/web/csp
    "'self'",
    'https://tagmanager.google.com',
    'https://www.googletagmanager.com/',
    'https://www.google.com/',
    'https://www.google-analytics.com/',
    'https://ssl.google-analytics.com',
    'https://adservice.google.com/',
    'https://ajax.googleapis.com/',
    'https://apis.google.com/',
    'https://unpkg.com/',
    'https://www.gstatic.com/',
    'https://apis.google.com/',
    'https://gstatic.com',
  ],
  'style-src': <String>[
    "'self'",
    'https://unpkg.com/',
    'https://pub.dartlang.org/static/', // older dartdoc content requires it
    "'unsafe-inline'", // package page (esp. analysis tab) required is
    'https://fonts.googleapis.com/',
    'https://gstatic.com',
    'https://www.gstatic.com/',
    'https://tagmanager.google.com',
  ],
};

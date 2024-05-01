// Copyright (c) 2024, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:pub_dev/frontend/static_files.dart';

import '../../account/models.dart';
import '../../admin/models.dart';
import '../dom/dom.dart' as d;
import '../dom/material.dart' as material;
import 'layout.dart';

const _subjectKindLabels = {
  ModerationSubjectKind.package: 'package',
  ModerationSubjectKind.packageVersion: 'package version',
  ModerationSubjectKind.publisher: 'publisher',
};

/// Renders the create publisher page.
String renderReportPage({
  SessionData? sessionData,
  required ModerationSubject subject,
}) {
  final kindLabel = _subjectKindLabels[subject.kind] ?? 'about';
  // TODO: also add `url`
  final lcpsDeepLink =
      Uri.parse('https://reportcontent.google.com/troubleshooter').replace(
    queryParameters: {
      'product': 'dart_pub',
      'content_id': subject.fqn,
    },
  );
  return renderLayoutPage(
    PageType.standalone,
    d.div(
      classes: ['report-main'],
      child: d.div(
        id: 'report-page-form',
        attributes: {
          'data-form-api-endpoint': '/api/report',
        },
        children: [
          d.h1(text: 'Report a problem'),
          d.p(children: [
            d.text('Why do you wish to report $kindLabel '),
            d.code(text: subject.localName),
            d.text('?'),
          ]),
          d.input(type: 'hidden', name: 'subject', value: subject.fqn),
          d.p(text: ''),
          // illegal content
          if (subject.hasPackage)
            _block(
              title: 'I believe the package contains illegal content.',
              children: [
                d.markdown('Please report illegal content through the '
                    '[illegal content reporting form here]($lcpsDeepLink).')
              ],
            )
          else if (subject.hasPublisher)
            _block(
              title: 'I believe the publisher contains illegal content.',
              children: [
                d.markdown('Please report illegal content through the '
                    '[illegal content reporting form here]($lcpsDeepLink).')
              ],
            ),

          // contact
          if (subject.hasPackage)
            _block(
              title:
                  'I have found a bug in the package / I need help using the package.',
              children: [
                d.markdown(
                    'Please consult the package page: `pub.dev/packages/${subject.package}`'),
                d.p(
                    text:
                        'Many packages have issue trackers, support discussion boards or chat rooms. '
                        'Often these are discoverable from the package source code repository.'),
                d.p(
                    text:
                        'Many packages are freely available and package authors '
                        'are not required to provide support.'),
                d.markdown(
                    'And the Dart team cannot provide support for all packages on pub.dev, '
                    'but it is often possible to get help and talk to other Dart developers through '
                    '[community channels](https://dart.dev/community).')
              ],
            )
          else if (subject.hasPublisher)
            _block(
              title: 'I want to contact the publisher.',
              children: [
                d.markdown(
                    'Please consult the publisher page: `pub.dev/publishers/<publisher>`'),
                d.p(
                    text: 'All publishers have a contact email. '
                        'Publishers do not have to provide support and may not respond to your inquiries.'),
              ],
            ),

          // direct report
          _block(
            classes: ['report-page-direct-report'],
            title: 'I believe the $kindLabel violates pub.dev/policy.',
            children: [
              if (!(sessionData?.isAuthenticated ?? false))
                d.fragment([
                  d.p(text: 'Contact information:'),
                  material.textField(
                    id: 'report-email',
                    name: 'email',
                    label: 'Email',
                  ),
                ]),
              d.p(text: 'Please describe the issue you want to report:'),
              material.textArea(
                id: 'report-message',
                name: 'message',
                label: 'Message',
                rows: 10,
                cols: 60,
                maxLength: 8192,
              ),
              material.raisedButton(
                label: 'Submit',
                id: 'report-submit',
                attributes: {
                  'data-form-api-button': 'submit',
                },
              ),
            ],
          ),

          // problem with pub.dev
          _block(
            title: 'I have a problem with the pub.dev website.',
            children: [
              d.markdown('Security vulnerabilities may be reported through '
                  '[goo.gl/vulnz](https://goo.gl/vulnz)'),
              d.markdown('Bugs on the pub.dev website may be reported at '
                  '[github.com/dart-lang/pub-dev/issues](https://github.com/dart-lang/pub-dev/issues)'),
              d.markdown(
                  'Issues with specific accounts may be directed to `support@pub.dev`.'),
            ],
          ),
        ],
      ),
    ),
    title: 'Report a problem',
    noIndex: true, // no need to index, may contain session-specific content
  );
}

d.Node _block({
  required String title,
  required Iterable<d.Node> children,
  List<String>? classes,
}) {
  return d.div(
    classes: ['report-page-section', 'foldable', ...?classes],
    children: [
      d.div(
        classes: ['report-page-section-title', 'foldable-button'],
        children: [
          d.img(
            classes: ['foldable-icon'],
            image: d.Image(
              src: staticUrls
                  .getAssetUrl('/static/img/report-foldable-icon.svg'),
              alt: 'trigger folding of the section',
              width: 13,
              height: 6,
            ),
          ),
          d.text(title),
        ],
      ),
      d.div(
        classes: ['report-page-section-body', 'foldable-content'],
        children: children,
      )
    ],
  );
}

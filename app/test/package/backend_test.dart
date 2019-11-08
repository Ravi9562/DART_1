// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

@Timeout(Duration(seconds: 15))
library pub_dartlang_org.backend_test;

import 'dart:async';

import 'package:gcloud/db.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'package:pub_dev/account/backend.dart';
import 'package:pub_dev/account/models.dart';
import 'package:pub_dev/package/backend.dart';
import 'package:pub_dev/package/models.dart';
import 'package:pub_dev/package/name_tracker.dart';
import 'package:pub_dev/package/upload_signer_service.dart';
import 'package:pub_dev/shared/exceptions.dart';

import '../shared/test_models.dart';
import '../shared/test_services.dart';

import 'backend_test_utils.dart';

void main() {
  group('backend', () {
    group('Backend.latestPackages', () {
      testWithServices('default packages', () async {
        final list = await packageBackend.latestPackages();
        expect(list.map((p) => p.name), [
          'foobar_pkg',
          'lithium',
          'helium',
          'hydrogen',
        ]);
      });

      testWithServices('default packages, extra earlier', () async {
        final h =
            (await dbService.lookup<Package>([helium.package.key])).single;
        h.updated = DateTime(2010);
        await dbService.commit(inserts: [h]);
        final list = await packageBackend.latestPackages();
        expect(list.last.name, 'helium');
      });

      testWithServices('default packages, extra later', () async {
        final h =
            (await dbService.lookup<Package>([helium.package.key])).single;
        h.updated = DateTime(2030);
        await dbService.commit(inserts: [h]);
        final list = await packageBackend.latestPackages();
        expect(list.first.name, 'helium');
      });

      testWithServices('default packages, offset: 2', () async {
        final list = await packageBackend.latestPackages(offset: 2);
        expect(list.map((p) => p.name), ['helium', 'hydrogen']);
      });

      testWithServices('default packages, offset: 1, limit: 1', () async {
        final list = await packageBackend.latestPackages(offset: 1, limit: 1);
        expect(list.map((p) => p.name), ['lithium']);
      });
    });

    group('Backend.latestPackageVersions', () {
      testWithServices('one package', () async {
        final list =
            await packageBackend.latestPackageVersions(offset: 2, limit: 1);
        expect(list.map((pv) => pv.qualifiedVersionKey.toString()),
            ['helium-2.0.5']);
      });

      testWithServices('empty', () async {
        final list =
            await packageBackend.latestPackageVersions(offset: 200, limit: 1);
        expect(list, isEmpty);
      });
    });

    group('Backend.lookupPackage', () {
      testWithServices('exists', () async {
        final p = await packageBackend.lookupPackage('hydrogen');
        expect(p, isNotNull);
        expect(p.name, 'hydrogen');
        expect(p.latestVersion, isNotNull);
      });

      testWithServices('does not exists', () async {
        final p = await packageBackend.lookupPackage('not_yet_a_package');
        expect(p, isNull);
      });
    });

    group('Backend.lookupPackageVersion', () {
      testWithServices('exists', () async {
        final p = await packageBackend.lookupPackage('hydrogen');
        final pv = await packageBackend.lookupPackageVersion(
            'hydrogen', p.latestVersion);
        expect(pv, isNotNull);
        expect(pv.package, 'hydrogen');
        expect(pv.version, p.latestVersion);
      });

      testWithServices('package does not exists', () async {
        final pv = await packageBackend.lookupPackageVersion(
            'not_yet_a_package', '1.0.0');
        expect(pv, isNull);
      });

      testWithServices('version does not exists', () async {
        final pv =
            await packageBackend.lookupPackageVersion('hydrogen', '0.0.0-dev');
        expect(pv, isNull);
      });
    });

    group('Backend.lookupLatestVersions', () {
      testWithServices('two packages', () async {
        final list = await packageBackend
            .lookupLatestVersions([hydrogen.package, helium.package]);
        expect(list.map((pv) => pv.qualifiedVersionKey.toString()),
            ['hydrogen-2.0.8', 'helium-2.0.5']);
      });
    });

    group('Backend.versionsOfPackage', () {
      testWithServices('exists', () async {
        final list = await packageBackend.versionsOfPackage('hydrogen');
        final values = list.map((pv) => pv.version).toList();
        values.sort();
        expect(values, hasLength(13));
        expect(values.first, '1.0.0');
        expect(values[5], '1.4.5');
        expect(values.last, '2.0.8');
      });

      testWithServices('package does not exists', () async {
        final list =
            await packageBackend.versionsOfPackage('not_yet_a_package');
        expect(list, isEmpty);
      });
    });

    group('Backend.downloadUrl', () {
      testWithServices('no escape needed', () async {
        final url = await packageBackend.downloadUrl('hydrogen', '2.0.8');
        expect(url.toString(),
            'http://localhost:0/fake-bucket-pub/packages/hydrogen-2.0.8.tar.gz');
      });

      testWithServices('version escape needed', () async {
        final url = await packageBackend.downloadUrl('hydrogen', '2.0.8+5');
        expect(url.toString(),
            'http://localhost:0/fake-bucket-pub/packages/hydrogen-2.0.8%2B5.tar.gz');
      });
    });
  });

  group('backend.repository', () {
    group('GCloudRepository.addUploader', () {
      testWithServices('not logged in', () async {
        final pkg = foobarPackage.name;
        final rs = packageBackend.repository.addUploader(pkg, 'a@b.com');
        await expectLater(rs, throwsA(isA<AuthenticationException>()));
      });

      testWithServices('not authorized', () async {
        final pkg = foobarPackage.name;
        registerAuthenticatedUser(User()
          ..id = 'uuid-foo-at-bar-dot-com'
          ..email = 'foo@bar.com');
        final rs = packageBackend.repository.addUploader(pkg, 'a@b.com');
        await expectLater(rs, throwsA(isA<AuthorizationException>()));
      });

      testWithServices('package does not exist', () async {
        registerAuthenticatedUser(hansUser);
        final rs =
            packageBackend.repository.addUploader('no_package', 'a@b.com');
        await expectLater(rs, throwsA(isA<NotFoundException>()));
      });

      Future testAlreadyExists(
          String pkg, List<User> uploaders, String newUploader) async {
        final bundle = generateBundle(pkg, ['1.0.0'], uploaders: uploaders);
        await dbService.commit(inserts: [
          bundle.package,
          ...bundle.versions.map(pvModels).expand((m) => m),
        ]);
        await packageBackend.repository.addUploader(pkg, newUploader);
        final list = await dbService.lookup<Package>([bundle.package.key]);
        final p = list.single;
        expect(p.uploaders, uploaders.map((u) => u.userId));
      }

      testWithServices('already exists', () async {
        registerAuthenticatedUser(hansUser);
        final ucEmail = 'Hans@Juergen.Com';
        await testAlreadyExists('p1', [hansUser], hansUser.email);
        await testAlreadyExists('p2', [hansUser], ucEmail);
        await testAlreadyExists('p3', [hansUser, joeUser], ucEmail);
        await testAlreadyExists('p4', [joeUser, hansUser], ucEmail);
      });

      testWithServices('successful', () async {
        registerAuthenticatedUser(hansUser);

        final newUploader = 'somebody@example.com';
        final rs = packageBackend.repository
            .addUploader(hydrogen.package.name, newUploader);
        await expectLater(
            rs,
            throwsA(isException.having(
                (e) => '$e',
                'text',
                'We have sent an invitation to $newUploader, '
                    'they will be added as uploader after they confirm it.')));

        // uploaders do not change yet
        final list = await dbService.lookup<Package>([hydrogen.package.key]);
        final p = list.single;
        expect(p.uploaders, [hansUser.userId]);

        expect(fakeEmailSender.sentMessages, hasLength(1));
        final email = fakeEmailSender.sentMessages.single;
        expect(email.recipients.single.email, 'somebody@example.com');
        expect(
            email.subject, 'You have a new invitation to confirm on pub.dev');
        expect(
            email.bodyText,
            contains(
                'hans@juergen.com has invited you to be an uploader of the package\nhydrogen.\n'));

        // TODO: check consent (after migrating to consent API)
      });
    });

    group('GCloudRepository.removeUploader', () {
      testWithServices('not logged in', () async {
        final rs = packageBackend.repository
            .removeUploader('hydrogen', hansUser.email);
        await expectLater(rs, throwsA(isA<AuthenticationException>()));
      });

      testWithServices('not authorized', () async {
        // replace uploader for the scope of this test
        final pkg =
            (await dbService.lookup<Package>([hydrogen.package.key])).single;
        pkg.addUploader(testUserA.userId);
        pkg.removeUploader(hansUser.userId);
        await dbService.commit(inserts: [pkg]);

        registerAuthenticatedUser(hansUser);
        final rs = packageBackend.repository
            .removeUploader('hydrogen', hansUser.email);
        await expectLater(rs, throwsA(isA<AuthorizationException>()));
      });

      testWithServices('package does not exist', () async {
        registerAuthenticatedUser(hansUser);
        final rs = packageBackend.repository
            .removeUploader('non_hydrogen', hansUser.email);
        await expectLater(rs, throwsA(isA<NotFoundException>()));
      });

      testWithServices('cannot remove last uploader', () async {
        registerAuthenticatedUser(hansUser);
        final rs = packageBackend.repository
            .removeUploader('hydrogen', hansUser.email);
        await expectLater(
            rs,
            throwsA(isException.having((e) => '$e', 'toString',
                'LastUploaderRemoved: Cannot remove last uploader of a package.')));
      });

      testWithServices('cannot remove non-existent uploader', () async {
        registerAuthenticatedUser(hansUser);
        final rs = packageBackend.repository
            .removeUploader('hydrogen', 'foo2@bar.com');
        await expectLater(
            rs,
            throwsA(isException.having((e) => '$e', 'toString',
                'The uploader to remove does not exist.')));
      });

      testWithServices('cannot remove self', () async {
        // adding extra uploader for the scope of this test
        final pkg =
            (await dbService.lookup<Package>([hydrogen.package.key])).single;
        pkg.addUploader(testUserA.userId);
        await dbService.commit(inserts: [pkg]);

        registerAuthenticatedUser(hansUser);
        final rs = packageBackend.repository
            .removeUploader('hydrogen', hansUser.email);
        await expectLater(
            rs,
            throwsA(isException.having((e) => '$e', 'toString',
                'Self-removal is not allowed. Use another account to remove this email address.')));
      });

      testWithServices('successful1', () async {
        // adding extra uploader for the scope of this test
        final key = hydrogen.package.key;
        final pkg1 = (await dbService.lookup<Package>([key])).single;
        pkg1.addUploader(testUserA.userId);
        await dbService.commit(inserts: [pkg1]);

        // verify before change
        final pkg2 = (await dbService.lookup<Package>([key])).single;
        expect(pkg2.uploaders, [hansUser.userId, testUserA.userId]);

        registerAuthenticatedUser(hansUser);
        await packageBackend.repository
            .removeUploader('hydrogen', testUserA.email);

        // verify after change
        final pkg3 = (await dbService.lookup<Package>([key])).single;
        expect(pkg3.uploaders, [hansUser.userId]);
      });
    });

    group('GCloudRepository.lookupVersion', () {
      testWithServices('package not found', () async {
        final version = await packageBackend.repository
            .lookupVersion('not_hydrogen', '1.0.0');
        expect(version, isNull);
      });

      testWithServices('version not found', () async {
        final version =
            await packageBackend.repository.lookupVersion('hydrogen', '0.3.0');
        expect(version, isNull);
      });

      testWithServices('successful', () async {
        final version =
            await packageBackend.repository.lookupVersion('hydrogen', '1.0.0');
        expect(version, isNotNull);
        expect(version.packageName, 'hydrogen');
        expect(version.versionString, '1.0.0');
      });
    });

    group('GCloudRepository.versions', () {
      testWithServices('not found', () async {
        final versions =
            await packageBackend.repository.versions('non_hydrogen').toList();
        expect(versions, isEmpty);
      });

      testWithServices('found', () async {
        final versions =
            await packageBackend.repository.versions('hydrogen').toList();
        expect(versions, isNotEmpty);
        expect(versions, hasLength(13));
        expect(versions.first.packageName, 'hydrogen');
        expect(versions.first.versionString, '1.0.0');
        expect(versions.last.packageName, 'hydrogen');
        expect(versions.last.versionString, '2.0.8');
      });
    });

    group('uploading', () {
      group('GCloudRepository.startAsyncUpload', () {
        testWithServices('no active user', () async {
          final rs = packageBackend.repository
              .startAsyncUpload(Uri.parse('http://example.com/'));
          await expectLater(rs, throwsA(isA<AuthenticationException>()));
        });

        testWithServices('successful', () async {
          final Uri redirectUri = Uri.parse('http://blobstore.com/upload');
          registerAuthenticatedUser(hansUser);
          final info =
              await packageBackend.repository.startAsyncUpload(redirectUri);
          expect(info.uri.toString(),
              startsWith('https://storage.url/fake-bucket-pub/tmp/'));
          expect(info.fields, {
            'key': startsWith('fake-bucket-pub/tmp/'),
            'success_action_redirect': startsWith('$redirectUri?upload_id='),
          });
        });
      });

      group('GCloudRepository.finishAsyncUpload', () {
        final Uri redirectUri =
            Uri.parse('http://blobstore.com/upload?upload_id=my-uuid');

        testWithServices('upload-too-big', () async {
          registerAuthenticatedUser(hansUser);

          final oneKB = List.filled(1024, 42);
          final bigTarball = <List<int>>[];
          for (int i = 0; i < UploadSignerService.maxUploadSize ~/ 1024; i++) {
            bigTarball.add(oneKB);
          }
          // Add one more byte than allowed.
          bigTarball.add([1]);

          final sink =
              packageBackend.repository.storage.bucket.write('tmp/my-uuid');
          bigTarball.forEach(sink.add);
          await sink.close();

          final rs = packageBackend.repository.finishAsyncUpload(redirectUri);
          await expectLater(
            rs,
            throwsA(
              isA<PackageRejectedException>().having(
                  (e) => '$e', 'text', contains('Package archive exceeded ')),
            ),
          );
        });

        testWithServices('successful', () async {
          registerAuthenticatedUser(hansUser);

          final dateBeforeTest = DateTime.now().toUtc();
          final pubspecContent = generatePubspecYaml('new_package', '1.2.3');
          await packageBackend.repository.storage.bucket.writeBytes(
              'tmp/my-uuid',
              await packageArchiveBytes(pubspecContent: pubspecContent));

          final version =
              await packageBackend.repository.finishAsyncUpload(redirectUri);
          expect(version.packageName, 'new_package');
          expect(version.versionString, '1.2.3');

          final pkgKey =
              dbService.emptyKey.append(Package, id: version.packageName);
          final package = (await dbService.lookup<Package>([pkgKey])).single;
          expect(package.name, 'new_package');
          expect(package.latestVersion, '1.2.3');
          expect(package.uploaders, ['hans-at-juergen-dot-com']);
          expect(package.publisherId, isNull);
          expect(package.created.compareTo(dateBeforeTest) >= 0, isTrue);
          expect(package.updated.compareTo(dateBeforeTest) >= 0, isTrue);

          final pvKey = package.latestVersionKey;
          final pv = (await dbService.lookup<PackageVersion>([pvKey])).single;
          expect(pv.packageKey, package.key);
          expect(pv.created.compareTo(dateBeforeTest) >= 0, isTrue);
          expect(pv.readmeFilename, 'README.md');
          expect(pv.readmeContent, foobarReadmeContent);
          expect(pv.changelogFilename, 'CHANGELOG.md');
          expect(pv.changelogContent, foobarChangelogContent);
          expect(pv.pubspec.asJson, loadYaml(pubspecContent));
          expect(pv.libraries, ['test_library.dart']);
          expect(pv.uploader, 'hans-at-juergen-dot-com');
          expect(pv.publisherId, isNull);
          expect(pv.downloads, 0);
          expect(pv.sortOrder, 0);

          expect(fakeEmailSender.sentMessages, hasLength(1));
          final email = fakeEmailSender.sentMessages.single;
          expect(email.recipients.single.email, hansUser.email);
          expect(email.subject, 'Package uploaded: new_package 1.2.3');
          expect(
              email.bodyText,
              contains(
                  'https://pub.dev/packages/new_package/versions/1.2.3\n'));

          // TODO: check history
          // TODO: check assets
        });

        testWithServices('package under publisher', () async {
          registerAuthenticatedUser(hansUser);

          final dateBeforeTest = DateTime.now().toUtc();
          final pubspecContent = generatePubspecYaml('lithium', '7.0.0');
          await packageBackend.repository.storage.bucket.writeBytes(
              'tmp/my-uuid',
              await packageArchiveBytes(pubspecContent: pubspecContent));

          final version =
              await packageBackend.repository.finishAsyncUpload(redirectUri);
          expect(version.packageName, 'lithium');
          expect(version.versionString, '7.0.0');

          final pkgKey =
              dbService.emptyKey.append(Package, id: version.packageName);
          final package = (await dbService.lookup<Package>([pkgKey])).single;
          expect(package.name, 'lithium');
          expect(package.latestVersion, '7.0.0');
          expect(package.publisherId, 'example.com');
          expect(package.uploaders, []);
          expect(package.created.compareTo(dateBeforeTest) < 0, isTrue);
          expect(package.updated.compareTo(dateBeforeTest) >= 0, isTrue);

          final pvKey = package.latestVersionKey;
          final pv = (await dbService.lookup<PackageVersion>([pvKey])).single;
          expect(pv.packageKey, package.key);
          expect(pv.created.compareTo(dateBeforeTest) >= 0, isTrue);
          expect(pv.readmeFilename, 'README.md');
          expect(pv.readmeContent, foobarReadmeContent);
          expect(pv.changelogFilename, 'CHANGELOG.md');
          expect(pv.changelogContent, foobarChangelogContent);
          expect(pv.pubspec.asJson, loadYaml(pubspecContent));
          expect(pv.libraries, ['test_library.dart']);
          expect(pv.uploader, 'hans-at-juergen-dot-com');
          expect(pv.publisherId, 'example.com');
          expect(pv.downloads, 0);
          expect(pv.sortOrder, 19);

          expect(fakeEmailSender.sentMessages, hasLength(1));
          final email = fakeEmailSender.sentMessages.single;
          expect(email.recipients.single.email, hansUser.email);
          expect(email.subject, 'Package uploaded: lithium 7.0.0');
          expect(email.bodyText,
              contains('https://pub.dev/packages/lithium/versions/7.0.0\n'));

          // TODO: check history
          // TODO: check assets
        });
      });

      group('GCloudRepository.upload', () {
        testWithServices('not logged in', () async {
          final tarball = await packageArchiveBytes();
          final rs =
              packageBackend.repository.upload(Stream.fromIterable([tarball]));
          await expectLater(rs, throwsA(isA<AuthenticationException>()));
        });

        testWithServices('not authorized', () async {
          registerAuthenticatedUser(joeUser);
          final tarball = await packageArchiveBytes(
              pubspecContent: generatePubspecYaml(foobarPackage.name, '0.2.0'));
          final rs =
              packageBackend.repository.upload(Stream.fromIterable([tarball]));
          await expectLater(rs, throwsA(isA<AuthorizationException>()));
        });

        testWithServices('versions already exist', () async {
          registerAuthenticatedUser(joeUser);
          final tarball = await packageArchiveBytes();
          final rs =
              packageBackend.repository.upload(Stream.fromIterable([tarball]));
          await expectLater(
              rs,
              throwsA(isA<Exception>().having(
                (e) => '$e',
                'text',
                contains(
                    'Version 0.1.1+5 of package foobar_pkg already exists'),
              )));
        });

        testWithServices('bad package names are rejected', () async {
          await nameTracker.scanDatastore();
          registerAuthenticatedUser(hansUser);

          // Returns the error message as String or null if it succeeded.
          Future<String> fn(String name) async {
            final pubspecContent = generatePubspecYaml(name, '0.2.0');
            try {
              final tarball =
                  await packageArchiveBytes(pubspecContent: pubspecContent);
              await packageBackend.repository
                  .upload(Stream.fromIterable([tarball]));
            } catch (e) {
              return e.toString();
            }
            // no issues, return null
            return null;
          }

          expect(await fn('with'),
              'Package name must not be a reserved word in Dart.');
          expect(await fn('123test'),
              'Package name must begin with a letter or underscore.');
          expect(await fn('With Space'),
              'Package name may only contain letters, numbers, and underscores.');

          expect(await fn('ok_name'), isNull);
        });

        testWithServices('upload-too-big', () async {
          registerAuthenticatedUser(hansUser);

          final oneKB = List.filled(1024, 42);
          final List<List<int>> bigTarball = [];
          for (int i = 0; i < UploadSignerService.maxUploadSize ~/ 1024; i++) {
            bigTarball.add(oneKB);
          }
          // Add one more byte than allowed.
          bigTarball.add([1]);

          final rs =
              packageBackend.repository.upload(Stream.fromIterable(bigTarball));
          await expectLater(
            rs,
            throwsA(
              isA<PackageRejectedException>().having(
                  (e) => '$e', 'text', contains('Package archive exceeded ')),
            ),
          );
        });

        testWithServices('successful upload + download', () async {
          registerAuthenticatedUser(hansUser);
          final tarball = await packageArchiveBytes(
              pubspecContent: generatePubspecYaml(foobarPackage.name, '1.2.3'));
          final version = await packageBackend.repository
              .upload(Stream.fromIterable([tarball]));
          expect(version.packageName, foobarPackage.name);
          expect(version.versionString, '1.2.3');

          expect(fakeEmailSender.sentMessages, hasLength(1));
          final email = fakeEmailSender.sentMessages.single;
          expect(email.recipients.single.email, hansUser.email);
          expect(email.subject, 'Package uploaded: foobar_pkg 1.2.3');
          expect(email.bodyText,
              contains('https://pub.dev/packages/foobar_pkg/versions/1.2.3\n'));

          final packages = await packageBackend.latestPackages();
          expect(packages.first.name, foobarPackage.name);
          expect(packages.first.latestVersion, '1.2.3');

          final stream = await packageBackend.repository
              .download(foobarPackage.name, '1.2.3');
          final chunks = await stream.toList();
          final bytes = chunks.fold<List<int>>(
              <int>[], (buffer, chunk) => buffer..addAll(chunk));
          expect(bytes, tarball);
        });
      });
    });
  });
}

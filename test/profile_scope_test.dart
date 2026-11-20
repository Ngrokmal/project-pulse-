import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse/features/profile/domain/pending_write.dart';
import 'package:pulse/features/profile/domain/profile_photo.dart';
import 'package:pulse/features/profile/domain/profile_privacy.dart';
import 'package:pulse/features/profile/domain/profile_scope.dart';
import 'package:pulse/features/profile/domain/profile_view_mode.dart';
import 'package:pulse/features/profile/domain/safety_action.dart';

void main() {
  group('scope plan', () {
    test('the two sets never intersect', () {
      final owner = ProfileAction.values
          .where((a) => ProfileScopePlan.allows(ProfileViewMode.owner, a))
          .toSet();
      final visitor = ProfileAction.values
          .where((a) => ProfileScopePlan.allows(ProfileViewMode.visitor, a))
          .toSet();

      expect(owner.intersection(visitor), isEmpty);
      expect(owner.union(visitor), ProfileAction.values.toSet());
    });

    test('the owner never gets a self-chat or a safety verb', () {
      final rows = ProfileScopePlan.moreSheet(ProfileViewMode.owner);
      expect(rows.contains(ProfileAction.message), isFalse);
      expect(rows.contains(ProfileAction.block), isFalse);
      expect(rows.contains(ProfileAction.report), isFalse);
      expect(
        ProfileScopePlan.dangerRows(ProfileViewMode.owner),
        isEmpty,
        reason: 'your own card has nothing to block',
      );
    });

    test('the visitor never gets an edit', () {
      for (final action in [
        ProfileAction.editCard,
        ProfileAction.changePhoto,
        ProfileAction.whoSeesWhat,
        ProfileAction.devices,
      ]) {
        expect(
          ProfileScopePlan.allows(ProfileViewMode.visitor, action),
          isFalse,
        );
      }
    });

    test('the primary label is short enough to never truncate at 390 px', () {
      for (final mode in ProfileViewMode.values) {
        expect(
          ProfileScopePlan.primary(mode).label.length,
          lessThanOrEqualTo(14),
        );
      }
      expect(
        ProfileScopePlan.primary(ProfileViewMode.owner).label,
        'Edit your card',
      );
      expect(
        ProfileScopePlan.primary(ProfileViewMode.visitor).label,
        'Message',
      );
    });

    test('quick actions are two, so the primary keeps its width', () {
      expect(ProfileScopePlan.quickActions(ProfileViewMode.owner).length, 2);
      expect(ProfileScopePlan.quickActions(ProfileViewMode.visitor).length, 2);
    });

    test('every destructive verb is visitor-only', () {
      for (final action in ProfileAction.values.where((a) => a.isDestructive)) {
        expect(action.owner, ProfileViewMode.visitor);
      }
    });
  });

  group('safety copy', () {
    test('a name fills the title, an empty name still reads', () {
      expect(SafetyAction.block.titleFor('Rifat'), 'Block Rifat');
      expect(SafetyAction.block.titleFor('  '), 'Block this person');
    });

    test('report reasons fit the column', () {
      for (final reason in ReportReason.values) {
        expect(reason.value.length, lessThanOrEqualTo(60));
      }
    });
  });

  group('pending write', () {
    PendingWrite write(Map<String, Object?> values, {DateTime? at}) =>
        PendingWrite(
          id: 'w1',
          userId: 'u1',
          values: values,
          createdAt: at ?? DateTime.now(),
        );

    test('a toggle is recognised as a privacy-only write', () {
      final pending = write({PrivacyField.readReceipts.column: false});
      expect(pending.privacyField, PrivacyField.readReceipts);
      expect(pending.isPrivacyOnly, isTrue);
    });

    test('a mixed write is not privacy-only, so it is never folded', () {
      final pending = write({
        PrivacyField.readReceipts.column: false,
        'status': 'Building Pulse, every night',
      });
      expect(pending.privacyField, PrivacyField.readReceipts);
      expect(pending.isPrivacyOnly, isFalse);
    });

    test('survives a round trip through json', () {
      final pending = write({PrivacyField.lastSeen.column: false});
      final again = PendingWrite.fromJson(
        Map<String, dynamic>.from(pending.toJson()),
      );
      expect(again.userId, 'u1');
      expect(again.values, pending.values);
      expect(again.privacyField, PrivacyField.lastSeen);
    });
  });

  group('photo crop', () {
    const landscape = Size(1200, 800);
    const portrait = Size(800, 1200);

    test('the crop always stays inside the image', () {
      for (final size in [landscape, portrait]) {
        for (final zoom in [PhotoCrop.minZoom, 1.7, PhotoCrop.maxZoom]) {
          final crop = PhotoCrop.identity
              .zoomedTo(zoom)
              .pannedBy(const Offset(400, -400), imageSize: size)
              .rebasedFor(size);
          final rect = crop.sourceRect(size);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width + 0.001));
          expect(rect.bottom, lessThanOrEqualTo(size.height + 0.001));
        }
      }
    });

    test('at 1x there is nowhere to pan on the covered axis', () {
      // A 3:2 photo covers the square on the short edge, so it may slide
      // sideways but never up and down.
      final crop = PhotoCrop.identity.pannedBy(
        const Offset(60, 60),
        imageSize: landscape,
      );
      expect(crop.offset.dy, 0);
      expect(crop.offset.dx, greaterThan(0));
    });

    test('zoom is clamped to the studio range', () {
      expect(PhotoCrop.identity.zoomedTo(9).zoom, PhotoCrop.maxZoom);
      expect(PhotoCrop.identity.zoomedTo(0.1).zoom, PhotoCrop.minZoom);
    });

    test('a fresh pick never inherits a wild pan', () {
      final wild = PhotoCrop(
        zoom: 2.4,
        offset: const Offset(500, 500),
      ).rebasedFor(landscape);
      final rect = wild.sourceRect(landscape);
      expect(rect.right, lessThanOrEqualTo(landscape.width + 0.001));
    });
  });
}

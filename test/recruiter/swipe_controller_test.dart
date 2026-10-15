import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/hiring_job.dart';
import 'package:hiring_app/models/swipe_filters.dart';
import 'package:hiring_app/models/swipe_models.dart';
import 'package:hiring_app/screens/recruiter/swipe/swipe_controller.dart';
import 'package:hiring_app/screens/recruiter/swipe/swipe_decision.dart';
import 'package:hiring_app/services/api_client.dart';
import 'package:hiring_app/services/hiring_service.dart';

import 'fake_hiring_service.dart';

void main() {
  late FakeHiringService service;
  late SwipeController c;
  late List<SwipeEvent> events;

  setUp(() {
    HiringService.swipesLeft.value = -1;
    service = FakeHiringService();
    c = SwipeController(service: service);
    events = [];
    c.onEvent = events.add;
  });

  tearDown(() => c.dispose());

  Future<void> start({int swipes = 5, List<String> ids = const ['a', 'b', 'c', 'd']}) async {
    service.serverSwipes = swipes;
    service.pages.add([for (final id in ids) card(id, name: 'Person $id')]);
    await c.init();
  }

  group('feed', () {
    test('first page is requested for the selected job and shown', () async {
      await start();
      expect(c.job?.id, 'j1');
      expect(c.stack.map((e) => e.id), ['a', 'b', 'c', 'd']);
      expect(c.viewState, SwipeViewState.ready);
      expect(service.feedCalls.single.jobId, 'j1');
    });

    test('never asks for more cards than swipes left', () async {
      await start(swipes: 3);
      expect(service.feedCalls.single.limit, 3);
      expect(c.stack.length, lessThanOrEqualTo(3));
    });

    test('with no swipes left the feed is not requested: out of swipes', () async {
      await start(swipes: 0);
      expect(service.feedCalls, isEmpty);
      expect(c.viewState, SwipeViewState.outOfSwipes);
    });

    test('loads more when fewer than 3 cards remain, excluding the stack and pending swipes', () async {
      await start(swipes: 20, ids: ['a', 'b', 'c']);
      expect(service.feedCalls.length, 1);
      service.pages.add([card('d'), card('e')]);
      final f = c.swipe(SwipeDir.left);
      await f;
      await pumpEventQueue();
      expect(service.feedCalls.length, 2);
      final second = service.feedCalls[1];
      expect(second.exclude, containsAll(['b', 'c']));
      expect(second.exclude, contains('a')); // in flight when it was requested
      expect(c.stack.map((e) => e.id), ['b', 'c', 'd', 'e']);
    });

    test('an empty page marks the feed as exhausted: seen everyone / no filter match', () async {
      await start(swipes: 5, ids: ['a']);
      service.pages.add([]);
      await c.swipe(SwipeDir.left);
      await pumpEventQueue();
      expect(c.viewState, SwipeViewState.seenEveryone);

      await c.setFilters(const SwipeFilters(location: 'Jaipur'));
      await pumpEventQueue();
      expect(c.viewState, SwipeViewState.noFilterMatch);
    });

    test('a feed error shows the error state and retry loads again', () async {
      service.feedError = ApiException(409, 'This job is paused or closed. Reopen it to see candidates.');
      await c.init();
      expect(c.viewState, SwipeViewState.error);
      expect(c.feedError, contains('paused or closed'));
      service.feedError = null;
      service.pages.add([card('a')]);
      await c.retry();
      expect(c.viewState, SwipeViewState.ready);
    });

    test('no open jobs', () async {
      service.jobs = [];
      await c.init();
      expect(c.viewState, SwipeViewState.noJobs);
      expect(service.feedCalls, isEmpty);
    });

    test('filters are sent to the feed and remembered per company', () async {
      await start();
      service.pages.add([card('z')]);
      const f = SwipeFilters(location: 'Pune', minExp: 2, skills: ['React']);
      await c.setFilters(f);
      expect(service.feedCalls.last.filters, f);
      expect(c.stack.map((e) => e.id), ['z']);
      expect(await service.loadFilters('c1'), f);
    });

    test('job change resets the stack and remembers the job', () async {
      service.jobs = [
        const HiringJob(id: 'j1', title: 'Frontend Dev'),
        const HiringJob(id: 'j2', title: 'Backend Dev'),
      ];
      await start();
      service.pages.add([card('x')]);
      await c.selectJob('j2');
      expect(c.job?.id, 'j2');
      expect(c.stack.map((e) => e.id), ['x']);
      expect(await service.lastJobId('c1'), 'j2');
      expect(c.undoCount, 0);
    });
  });

  group('swipe', () {
    test('right swipe is optimistic, then confirmed with the contact email', () async {
      await start();
      final future = c.swipe(SwipeDir.right);
      // Before the server answered:
      expect(c.stack.first.id, 'b');
      expect(HiringService.swipesLeft.value, 4);
      expect(c.pendingCount, 1);
      await future;
      expect(service.swipeCalls.single, (id: 'a', action: 'right', jobId: 'j1'));
      expect(HiringService.swipesLeft.value, 4);
      expect(c.undoCount, 1);
      expect(c.canUndo, isTrue);
      final flash = events.firstWhere((e) => e.type == SwipeEventType.shortlisted);
      expect(flash.email, 'asha@example.com');
      expect(flash.candidate?.id, 'a');
    });

    test('left swipe sends "left" and shows no flash', () async {
      await start();
      await c.swipe(SwipeDir.left);
      expect(service.swipeCalls.single.action, 'left');
      expect(events.where((e) => e.type == SwipeEventType.shortlisted), isEmpty);
    });

    test('with no swipes left the paywall opens and nothing is sent', () async {
      await start(swipes: 1);
      HiringService.swipesLeft.value = 0;
      await c.swipe(SwipeDir.right);
      expect(events.single.type, SwipeEventType.paywall);
      expect(service.swipeCalls, isEmpty);
      expect(c.stack.first.id, 'a');
    });

    test('NO_SWIPES puts the card back, zeroes the counter and opens the paywall', () async {
      await start();
      service.swipeError = ApiException(
        402,
        'You have used all your swipes. Buy a plan to keep swiping.',
        body: {'code': 'NO_SWIPES'},
      );
      await c.swipe(SwipeDir.right);
      expect(c.stack.first.id, 'a');
      expect(HiringService.swipesLeft.value, 0);
      expect(events.last.type, SwipeEventType.paywall);
      expect(c.undoCount, 0);
    });

    test('SALARY_MISMATCH toasts for 6s, restores the credit and does not put the card back', () async {
      await start();
      service.swipeError = ApiException(
        409,
        'Asha expects at least ₹12 LPA, above this job\'s budget of ₹8 LPA, and is not open to negotiate.',
        body: {'code': 'SALARY_MISMATCH'},
      );
      await c.swipe(SwipeDir.right);
      expect(c.stack.first.id, 'b');
      expect(HiringService.swipesLeft.value, 5);
      final e = events.last;
      expect(e.type, SwipeEventType.errorToast);
      expect(e.duration, const Duration(seconds: 6));
      expect(e.message, contains('not open to negotiate'));
    });

    test('a duplicate swipe (409) is silent and restores the credit', () async {
      await start();
      service.swipeError = ApiException(409, 'You have already swiped this candidate for this job');
      await c.swipe(SwipeDir.left);
      expect(events, isEmpty);
      expect(HiringService.swipesLeft.value, 5);
      expect(c.stack.first.id, 'b');
    });

    test('any other error puts the card back with an error toast', () async {
      await start();
      service.swipeError = ApiException(0, 'Network error. Check your connection and try again.');
      await c.swipe(SwipeDir.right);
      expect(c.stack.first.id, 'a');
      expect(HiringService.swipesLeft.value, 5);
      expect(events.last.type, SwipeEventType.errorToast);
    });

    test('the server balance corrects the optimistic one', () async {
      await start();
      service.serverSwipes = 9; // e.g. a purchase on another device
      await c.swipe(SwipeDir.left);
      expect(HiringService.swipesLeft.value, 8);
    });
  });

  group('undo', () {
    test('undoing a pass refunds, brings the card back and says so', () async {
      await start();
      await c.swipe(SwipeDir.left);
      expect(c.stack.first.id, 'b');
      service.undoResult = UndoResult(swipesLeft: 5, action: 'left', jobId: 'j1', card: card('a'));
      await c.undo();
      expect(c.stack.first.id, 'a');
      expect(HiringService.swipesLeft.value, 5);
      expect(c.undoCount, 0);
      final e = events.last;
      expect(e.type, SwipeEventType.undone);
      expect(e.message, 'Pass undone, swipe refunded');
      expect(e.action, 'left');
    });

    test('undoing a shortlist is not refunded', () async {
      await start();
      await c.swipe(SwipeDir.right);
      service.undoResult = UndoResult(swipesLeft: 4, action: 'right', jobId: 'j1', card: card('a'));
      await c.undo();
      expect(HiringService.swipesLeft.value, 4);
      expect(events.last.message, startsWith('Shortlist undone. Its swipe is not refunded'));
    });

    test('a card of another job is not put back', () async {
      await start();
      await c.swipe(SwipeDir.left);
      service.undoResult = UndoResult(swipesLeft: 5, action: 'left', jobId: 'other', card: card('a'));
      await c.undo();
      expect(c.stack.first.id, 'b');
    });

    test('404 resets the undo count and shows the message', () async {
      await start();
      await c.swipe(SwipeDir.left);
      service.undoError = ApiException(404, 'There is no recent swipe to undo');
      await c.undo();
      expect(c.undoCount, 0);
      expect(c.canUndo, isFalse);
      expect(events.last.message, 'There is no recent swipe to undo');
    });

    test('409 shows the message', () async {
      await start();
      await c.swipe(SwipeDir.right);
      service.undoError =
          ApiException(409, 'You have already contacted this candidate, so this swipe cannot be undone');
      await c.undo();
      expect(events.last.type, SwipeEventType.errorToast);
      expect(events.last.message, contains('already contacted'));
    });

    test('nothing to undo before a swipe', () async {
      await start();
      expect(c.canUndo, isFalse);
      await c.undo();
      expect(service.undoCalls, 0);
    });
  });

  group('wishlist', () {
    test('toggles optimistically and toasts', () async {
      await start();
      final f = c.toggleWishlist();
      expect(c.top!.wishlisted, isTrue);
      await f;
      expect(service.wishlistCalls.single, (id: 'a', value: true));
      expect(events.last.message, 'Added to wishlist');
    });

    test('reverts on error', () async {
      await start();
      service.wishlistError = ApiException(500, 'boom');
      await c.toggleWishlist();
      expect(c.top!.wishlisted, isFalse);
      expect(events.last.type, SwipeEventType.errorToast);
    });
  });

  group('saved searches', () {
    test('saving needs a name and at least one filter', () async {
      await start();
      expect(await c.saveSearch('', const SwipeFilters(location: 'x')), 'Give this search a name');
      expect(await c.saveSearch('A', const SwipeFilters()), 'Set at least one filter before saving the search');
    });

    test('alerts toggle is optimistic and reverts on error', () async {
      await start();
      const search = SavedSearch(id: 's1', name: 'React devs', filters: SwipeFilters(skills: ['React']), alerts: true);
      c.searches = [search];
      await c.toggleSearchAlerts(search);
      expect(c.searches.first.alerts, isFalse);
      expect(service.alertCalls.single, (id: 's1', alerts: false));

      service.searchError = ApiException(500, 'boom');
      await c.toggleSearchAlerts(c.searches.first);
      expect(c.searches.first.alerts, isFalse); // reverted to the previous value
      expect(events.last.type, SwipeEventType.errorToast);
    });

    test('a saved search is added to the list and deleting removes it', () async {
      await start();
      final err = await c.saveSearch('Jaipur React', const SwipeFilters(location: 'Jaipur'));
      expect(err, isNull);
      expect(c.searches.single.name, 'Jaipur React');
      await c.deleteSearch(c.searches.single);
      expect(c.searches, isEmpty);
      expect(service.deletedSearches, ['new']);
    });

    test('a search id from a notification applies its filters', () async {
      service.searches = [
        const SavedSearch(id: 's9', name: 'Jaipur', filters: SwipeFilters(location: 'Jaipur')),
      ];
      await start();
      service.pages.add([card('q')]);
      await c.applySearchById('s9');
      expect(c.filters.location, 'Jaipur');
      expect(service.feedCalls.last.filters.location, 'Jaipur');
    });
  });
}

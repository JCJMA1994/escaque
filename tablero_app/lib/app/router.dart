import 'package:go_router/go_router.dart';

import '../account/auth_screen.dart';
import '../account/username_screen.dart';
import '../learn/learn_screen.dart';
import '../social/friends_screen.dart';
import '../social/leaderboard_screen.dart';
import '../match/match_config.dart';
import '../puzzles/puzzle_list_screen.dart';
import '../screens/join_invite_screen.dart';
import '../screens/settings_screen.dart';
import '../puzzles/puzzle_screen.dart';
import '../account/verify_email_screen.dart';
import '../onboarding/onboarding_screen.dart';
import 'app_flags.dart';
import '../data/game_store.dart';
import '../screens/game_screen.dart';
import '../screens/home_screen.dart';
import '../screens/new_game_screen.dart';
import '../screens/online_game_loader.dart';
import '../screens/online_lobby_screen.dart';
import '../screens/result_screen.dart';
import '../screens/review_screen.dart';

final appRouter = GoRouter(
  refreshListenable: AppFlags.onboardingDone,
  // La primera vez, la presentación; la cuenta es accesible desde ella.
  redirect: (context, state) {
    final loc = state.matchedLocation;
    // Las invitaciones (/j/CÓDIGO) entran sin pasar por la presentación.
    final open = loc.startsWith('/welcome') || loc.startsWith('/account') || loc.startsWith('/j/');
    if (!AppFlags.onboardingDone.value && !open) return '/welcome';
    return null;
  },
  routes: [
    GoRoute(path: '/welcome', builder: (context, state) => const OnboardingScreen()),
    GoRoute(
      path: '/account',
      builder: (context, state) => AuthScreen(next: state.uri.queryParameters['next'] ?? '/'),
    ),
    GoRoute(
      path: '/account/username',
      builder: (context, state) => UsernameScreen(
        next: state.uri.queryParameters['next'] ?? '/',
        change: state.uri.queryParameters['change'] == '1',
      ),
    ),
    GoRoute(
      path: '/account/verify',
      builder: (context, state) => VerifyEmailScreen(next: state.uri.queryParameters['next'] ?? '/'),
    ),
    GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
    GoRoute(
      path: '/new/:kind',
      builder: (context, state) =>
          NewGameScreen(kind: GameKind.values.byName(state.pathParameters['kind']!)),
    ),
    GoRoute(path: '/game', builder: (context, state) => const GameScreen()),
    GoRoute(
      path: '/j/:code',
      builder: (context, state) => JoinInviteScreen(code: state.pathParameters['code'] ?? ''),
    ),
    GoRoute(
      path: '/learn',
      builder: (context, state) => LearnListScreen(
        kind: _kindByName(state.uri.queryParameters['kind']),
      ),
    ),
    GoRoute(
      path: '/learn/:id',
      builder: (context, state) => LessonScreen(lessonId: state.pathParameters['id'] ?? ''),
    ),
    GoRoute(path: '/remove-ads', builder: (context, state) => const RemoveAdsScreen()),
    GoRoute(path: '/puzzles', builder: (context, state) => const PuzzleListScreen()),
    GoRoute(
      path: '/puzzles/:id',
      builder: (context, state) => PuzzleScreen(
        puzzleId: int.tryParse(state.pathParameters['id'] ?? '') ?? 1,
        daily: state.uri.queryParameters['daily'] == '1',
      ),
    ),
    GoRoute(path: '/online', builder: (context, state) => const OnlineLobbyScreen()),
    GoRoute(path: '/friends', builder: (context, state) => const FriendsScreen()),
    GoRoute(path: '/leaderboards', builder: (context, state) => const LeaderboardScreen()),
    GoRoute(
      path: '/online/game/:id',
      builder: (context, state) => OnlineGameLoader(gameId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/result',
      builder: (context, state) => ResultScreen(summary: state.extra! as MatchSummary),
    ),
    GoRoute(
      path: '/review',
      builder: (context, state) => ReviewScreen(game: state.extra! as SavedGame),
    ),
  ],
);

GameKind? _kindByName(String? name) {
  for (final k in GameKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

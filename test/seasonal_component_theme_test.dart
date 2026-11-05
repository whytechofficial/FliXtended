import 'package:flixquest/constants/theme_data.dart';
import 'package:flixquest/models/app_colors.dart';
import 'package:flixquest/models/occasional_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('seasonal theme contributes effects only; base colors own it',
      (tester) async {
    late ThemeData baseTheme;
    late ThemeData seasonalTheme;
    final occasionalTheme = OccasionalTheme.fromJson(<String, dynamic>{
      'id': 'custom_launch',
      'enabled': true,
      'colors': <String>['#7B1FA2', '#00897B'],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            baseTheme = Styles.themeData(
              appThemeMode: 'dark',
              isM3Enabled: true,
              lightDynamicColor: null,
              darkDynamicColor: null,
              context: context,
              appColor: AppColor(
                cs: AppColor.colorGetter(Colors.deepPurple, true),
                index: 1,
              ),
            );
            seasonalTheme = Styles.themeData(
              appThemeMode: 'dark',
              isM3Enabled: true,
              lightDynamicColor: null,
              darkDynamicColor: null,
              context: context,
              appColor: AppColor(
                cs: AppColor.colorGetter(Colors.deepPurple, true),
                index: 1,
              ),
              occasionalTheme: occasionalTheme,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // A seasonal theme must not override any base color: the accent,
    // the controls and the surfaces all stay exactly the base theme's.
    // (Seasonal effects render in a separate overlay layer.)
    expect(seasonalTheme.colorScheme.primary, baseTheme.colorScheme.primary);
    expect(
      seasonalTheme.colorScheme.primary,
      isNot(occasionalTheme.primaryColor),
    );
    expect(
      seasonalTheme.radioTheme.fillColor?.resolve(<WidgetState>{}),
      baseTheme.radioTheme.fillColor?.resolve(<WidgetState>{}),
    );
    expect(
      seasonalTheme.checkboxTheme.fillColor
          ?.resolve(<WidgetState>{WidgetState.selected}),
      baseTheme.checkboxTheme.fillColor
          ?.resolve(<WidgetState>{WidgetState.selected}),
    );
    expect(seasonalTheme.progressIndicatorTheme.color,
        baseTheme.progressIndicatorTheme.color);
    expect(seasonalTheme.sliderTheme.activeTrackColor,
        baseTheme.sliderTheme.activeTrackColor);
    expect(seasonalTheme.sliderTheme.thumbColor,
        baseTheme.sliderTheme.thumbColor);
    expect(seasonalTheme.textSelectionTheme.cursorColor,
        baseTheme.textSelectionTheme.cursorColor);
    expect(seasonalTheme.badgeTheme.backgroundColor,
        baseTheme.badgeTheme.backgroundColor);
    expect(seasonalTheme.scaffoldBackgroundColor,
        baseTheme.scaffoldBackgroundColor);

    // Icons, buttons and navigation likewise follow the base theme.
    expect(seasonalTheme.iconTheme.color, baseTheme.iconTheme.color);
    expect(
      seasonalTheme.iconButtonTheme.style?.foregroundColor
          ?.resolve(<WidgetState>{}),
      baseTheme.iconButtonTheme.style?.foregroundColor
          ?.resolve(<WidgetState>{}),
    );
    expect(seasonalTheme.floatingActionButtonTheme.foregroundColor,
        baseTheme.floatingActionButtonTheme.foregroundColor);
    expect(seasonalTheme.bottomNavigationBarTheme.selectedItemColor,
        baseTheme.bottomNavigationBarTheme.selectedItemColor);
    expect(seasonalTheme.navigationRailTheme.selectedIconTheme?.color,
        baseTheme.navigationRailTheme.selectedIconTheme?.color);

    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: seasonalTheme,
        home: Scaffold(
          body: Row(
            children: <Widget>[
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.share),
              ),
              IconButton.filledTonal(
                onPressed: () {},
                icon: const Icon(Icons.bookmark),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final shareContext = tester.element(find.byIcon(Icons.share));
    expect(Theme.of(shareContext).useMaterial3, seasonalTheme.useMaterial3);
    expect(Theme.of(shareContext).iconTheme.color,
        baseTheme.iconTheme.color);
    expect(IconTheme.of(shareContext).color, baseTheme.iconTheme.color);
    expect(
      IconTheme.of(tester.element(find.byIcon(Icons.bookmark))).color,
      isNot(Colors.deepPurple),
    );
  });
}

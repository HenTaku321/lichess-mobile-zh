import 'package:lichess_mobile/src/model/xiangqi/xiangqi_position_validation.dart';
import 'package:lichess_mobile/src/utils/l10n_context.dart';
import 'package:material_ui/material_ui.dart';

/// The same safety boundary applies to an editor, teaching diagram and directly imported FEN.
String xiangqiPositionErrorLabel(BuildContext context, XiangqiPositionError error) =>
    switch (error) {
      .generals => context.l10n.mobileXiangqiInvalidGenerals,
      .counters => context.l10n.mobileXiangqiInvalidCounters,
      .material => context.l10n.mobileXiangqiInvalidMaterial,
      .placement => context.l10n.mobileXiangqiInvalidPlacement,
      .facingGenerals => context.l10n.mobileXiangqiFacingGenerals,
      .inactiveSideInCheck => context.l10n.mobileXiangqiInactiveSideInCheck,
    };

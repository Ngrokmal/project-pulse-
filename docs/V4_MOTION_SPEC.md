# V4 Motion Spec (frozen)

Source of truth: `pulse-home-reference-v4.html` (approved).

This file is the **contract** for the Flutter port. Every value below was read
off the HTML/CSS — nothing is invented. If a later change is needed it must be
changed here first, then in code.

## What is being ported — and what is not

**Being ported:** logic, motion, color, depth, beauty — the *system*.

**Not being ported:** the demo content. The mock rows (`Jannat`, `Friends
Group`, `Study Buddies`, …), the mock clock `9:41`, the wifi/battery status bar,
the `8:45 PM` timestamps and the "Notifications" sheet copy are all placeholders
from the reference. The app renders **real conversations from the database**
and the **real OS status bar** — the app never draws its own status bar.

Layout is fluid: the reference is a fixed 396×820 artboard; the app fills the
real device (safe areas, notches, tablets, landscape). Ratios that must survive
the stretch: avatar 62 : row padding 10, name 17.5 : preview 14.5, radius 22,
vertical rhythm 10 px between cards.

## Tokens

| Token | Value | Where |
|---|---|---|
| brand 500 / 600 / 700 | `#7B5FED` / `#5F3FDC` / `#4F25C4` | `AppColors` (already) |
| bg / card / border | `#F8F7FB` / `#FFFFFF` / `#ECEAF4` | `AppColors` (already) |
| online / danger | `#17C653` / `#EF3E4A` | `AppColors` (already) |
| name ink | `#141452` | row only |
| preview ink | `#6F6C80` | row only |
| row radius | 22 | `PulseMotion.rowRadius` |
| row avatar | 62 | `PulseMotion.avatarSize` |
| row shadow | `0 12px 26px -16px rgba(95,63,220,.55)`, `0 3px 10px rgba(21,20,24,.045)`, `0 14px 14px -16px rgba(95,63,220,.45)` | `PulseMotion.rowShadow` |

## Curves

| Name | CSS | Flutter |
|---|---|---|
| spring | `cubic-bezier(.22,1.18,.36,1)` | `Cubic(0.22, 1.18, 0.36, 1)` |
| easeOut | `cubic-bezier(.16,1,.3,1)` | `Cubic(0.16, 1, 0.3, 1)` |
| ring | `cubic-bezier(.25,.7,.3,1)` | `Cubic(0.25, 0.7, 0.3, 1)` |

## Motion

| Effect | Value |
|---|---|
| Row entrance | 620 ms, rise 20 px, scale .972→1, blur 7 px→0 |
| Row stagger | 26 ms per index |
| Tab switch glide (FLIP) | 560 ms, old position → new position, blur 2.6 px→0 |
| Press (sink) | hold: translateY 2.5 px, scale .99, shadow softened; starts at 0 ms |
| Release (lift) | 540 ms, overshoot −1.8 px, scale 1.005 at 52 % |
| Card press radius | same 22 |
| Water droplet | scale .22→6.2, 780 ms, ease `.18,.7,.32,1` |
| Water ring 1 | scale .5→6.3, 920 ms linear, stroke 2.2→0.8 px |
| Water ring 2 | same, +140 ms delay, 1020 ms |
| Spray beads | 3 at (−30,−18) (26,−22) (12,24), 720 ms, 45 ms apart |
| Search open | 480 ms spring, height 0→58, brand slides out 20 px + blur 3 px |
| Search items in | icon 100 ms, text 150 ms, close 210 ms |
| List recede | blur 1.6 px, opacity .42, scale .982 |
| Non-match row | blur 2.2 px, opacity .42 |
| Top/bottom feather | transparent→opaque over 26 px at the top, `h−42px`→bottom |
| Chat route | 520 ms spring slide + 400 ms fade |
| Bubble in | 580 ms, rise 24 px, scale .93, blur 7 px, 45 ms stagger |
| Ticks | 620 ms → sent, 1200 ms → delivered, 2450 ms → seen |

## Blur policy

Blur is real (`ImageFilter`) but goes through `PulseMotion.blur(px)`. If
`PulseMotion.blurEnabled` is false every blur collapses to 0 and the app keeps
the opacity/scale part of each animation. Frame timing decides the default on a
real device; the switch exists so a slow phone degrades instead of stuttering.

## Phasing

- **P0** this document
- **A** `PulseMotion` + water ripple + press/lift
- **B** row v4 look + entrance + scroll depth + edge feather
- **C** search spotlight + tab movement
- **D** chat screen + tick state machine
- **E** theme wiring / font (Poppins already bundled)
- **F** server: `delivered_at`, `seen_at`, `last_seen_at`, presence
- **G** HTML-vs-Flutter screenshot diff loop + golden tests
- **H** CI + release APK

Standing honesty rule: nothing is reported "done" until it has a command and an
output behind it, and nothing is claimed on-device until it has run on a phone.

---

## 实施状态（滚动更新）

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| 0 | tokens（`PulseMotion`） | ✅ 完成 |
| A | 行重构：62 头像 / 22 圆角 / 三层阴影 / 名字与预览墨色 | ✅ 完成 |
| B | 入场 stagger + blur→sharp + 上下 feather（`PulseEdgeFade`） | ✅ 完成 |
| C | 按压下沉 2.5px + 回弹 + 水波（`PulseTapSurface`） | ✅ 完成 |
| D | 搜索 spotlight（整页后退、仅命中项上浮） | ⬜ 未开始 |
| E | 过滤 tab FLIP | ⬜ 未开始 |
| F | 聊天页气泡入场 + tick 状态机（需 `lastMessageStatus` 列） | ⬜ 未开始 |
| G | 群组页/通话页的动作套用 | ⬜ 未开始 |
| H | 真机性能核对（`--profile`，Raster/UI 线程） | ⬜ 未开始 |

### 已验证（可复现）

```bash
export PATH=/home/user/.cache/tools/flutter/bin:$PATH
cd /home/user/project-pulse
flutter analyze                       # 0 issues
flutter test                          # 153 passed, 5 skipped
flutter test test/qa/preview_frames_test.dart --run-skipped --update-goldens
# → test/qa/frames/*.png  逐帧截图（入场 140/300ms、按压 70/330/630ms、滚动 180/600）
```

### 与 v4 的两处刻意差异

1. **滚动时的行淡出**：v4 用 CSS `mask-image` 做连续渐变；Flutter 侧用一层
   `ShaderMask`（`PulseEdgeFade`, 26px / 42px）实现同样效果 —— 不是逐行设透明度，
   逐行会让淡出看起来一节一节跳。
2. **入场只在首屏播放**：列表滚动后才建出来的行直接就位（`PulseRowMotion` 判断
   `position.pixels > 0`），否则快速滚动时会不断有行"重新晕开"，读起来像卡顿。

## 0.6.5

- make sure the first frame is loaded before receiving `mediaInfo` in ios/macos.

## 0.6.4

- fixed a bug may cause video freeze on ios/macos.
- **breaking change:** replace `SetStateSafely` mixin with `SetStateAsync`.

## 0.6.3

- minor fixes.

## 0.6.2

- fix code formatting issues.

## 0.6.1

- `seekTo` won't increase `finishedTimes` any more if the player is not in `playing` state.
- auto correct param values in `seekTo`, `setVolume` and `setSpeed` methods.

## 0.6.0

- fix type mismatch issue in android seekTo method.

## 0.5.9

- check current position in seekTo calls from native side.

## 0.5.8

- interduce `SetStateSafely` mixin to prevent errors while `setState` is called on a bad time.

## 0.5.7

- **breaking change:** remove `keepAspectRatio` property from `AVMediaView` widget and add `sizingMode` property instead.

## 0.5.6

- fix setState issue in `AVMediaView` widget

## 0.5.5

- improve vsync handling on ios/macos
- improve dartdoc comments

## 0.5.4

- improve vsync handling on macos
- fixed a resource leak issue on ios/macos

## 0.5.3

- improve dartdoc comments
- improve examples
- combine macos and ios backend code
- add `backgroundColor` and `keepAspectRatio` support for `AVMediaView` widget

## 0.5.2

- add dartdoc comments
- change default example to the simple one

## 0.5.1

- first public release.

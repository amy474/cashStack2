# CashStack

A wallet that shows the money in your bank accounts as actual cash — notes and
coins, in multiples, piled up and obeying gravity. Tip the phone and the pile
sloshes. To pay, you hold a note and swipe it off the top of the screen, and
your change falls back down.

This is a working demo: a native iOS app, TestFlight-ready, with the bank layer
behind a protocol so real institutions can be plugged in.

![Loose and sorted](docs/screens.png)

## Running it

```bash
open CashStack.xcodeproj
```

Pick an iPhone simulator and hit run. From the command line:

```bash
xcodebuild -project CashStack.xcodeproj -scheme CashStack -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

Gravity comes from CoreMotion, so the sloshing only really shows on a device.
On the Simulator the pile falls straight down and the holographic sheen runs on
a timer instead of on tilt.

## The idea

| | |
|---|---|
| **Loose** | The physics pile. Every piece of money is a body in a SpriteKit world whose gravity vector is the phone's own. Shake it and the pile jumps. |
| **Sorted** | The same cash, counted: denomination, count, subtotal, total. For when you need the number, not the feeling. |
| **Pay** | The merchant's amount sits at the top. Press and hold a note, swipe it above the dashed line, let go. It's gone. Hand over too much and the change falls in from the top of the screen. |

The pile is the source of truth, not a freshly-computed breakdown. Pay for a
£4.45 coffee with a £20 and you are genuinely carrying £15.55 of change
afterwards — a £10, a £5, two 20p and a 5p — until you tap **tidy**
(the stack icon, bottom left), which re-breaks the balance into the fewest
possible pieces.

## How it is put together

```
CashStack/
  Model/Denomination.swift     Sterling denominations, sizes, and the breakdown maths
  Banking/BankDataSource.swift The protocol every bank conforms to, plus the demo source
  Banking/WalletStore.swift    Merges accounts, holds the pile, settles payments
  Physics/CashScene.swift      SpriteKit world: gravity, walls, the pay line, drag-to-pay
  Physics/MoneyNode.swift      One note or coin as a physics body
  Physics/MotionManager.swift  CoreMotion gravity and shake, delivered by closure
  Design/MoneyArt.swift        The notes and coins, drawn at runtime — no image assets
  Design/HoloShine.swift       The holographic shader
  Views/                       SwiftUI chrome, sorted view, accounts, till
```

**Design.** White ground, black hairlines at 1pt, SF Rounded throughout, bright
money. The notes and coins are drawn with CoreGraphics at launch and cached, so
there is nothing to redraw and nothing to ship.

**The holographic shine** is a fragment shader on each piece of money
(`Design/HoloShine.swift`). A rainbow band sweeps diagonally on a slow loop,
staggered across four shader instances so the pieces do not all flash together,
and a second softer sheen tracks the device's roll — so the foil catches the
light as the handset moves. In the sorted view the SwiftUI thumbnails get the
same treatment with an animated gradient (`Design/Components.swift`).

**Motion** is read at 60Hz and handed to the scene by closure rather than
`@Published`, which would re-render the whole SwiftUI tree sixty times a second.

## Connecting real banks

Everything above `BankDataSource` is ignorant of where a balance came from:

```swift
protocol BankDataSource: AnyObject {
    var institution: Institution { get }
    func connect() async throws
    func accounts() async throws -> [LinkedAccount]
    func debit(accountID: String, minor: Int) async throws
}
```

`WalletStore` holds an array of these and merges whatever they return, so
multi-bank aggregation is just "add another source". To go live, write one
conforming type per route — an Open Banking AISP (TrueLayer, Plaid, Yapily) or a
bank's own API — have `connect()` run the consent flow, and pass it to
`WalletStore.link(_:)`. Nothing else changes. The demo ships three
`DemoBankDataSource` instances with in-memory balances and a deliberate delay so
the loading states are real.

`debit` is where a demo and a real wallet part company: here it decrements a
number, whereas a shipping app would initiate a payment and only move the cash
on screen once the payment is confirmed.

## Tests

```bash
xcodebuild -project CashStack.xcodeproj -scheme CashStack -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

`CashStackUITests` drives the real gestures. Every piece of money is named after
its denomination, which puts it in the accessibility tree, so a test can pick up
a particular £20 note and swipe it to the top exactly as a person would. The
suite covers the balance breaking into the right notes and coins, the
hold-and-swipe payment, change arriving, tidying, and accounts going in and out
of the pile.

`ScreenshotTests` walks the app through every screen and attaches a shot of each.

> If a test fails in a way that makes no sense, delete the app off the simulator
> first — `xcrun simctl uninstall booted com.bokscot.cashstack`. A stale install
> will happily run old code against new tests.

## TestFlight

The project archives for device as-is; it only needs signing details.

1. In **Signing & Capabilities**, pick your team. The bundle id is
   `com.bokscot.cashstack` — change it to one your team owns.
2. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in the build settings.
3. **Product ▸ Archive**, then **Distribute App ▸ TestFlight**.

Already in place: portrait-only, light appearance, iOS 17 minimum, a 1024px app
icon in the asset catalog, no third-party dependencies, and no private API use.
CoreMotion's device motion needs no usage description, so there is no extra
privacy string to write.

Before a public release you would still need an App Privacy declaration covering
the financial data the bank connections read.

## What this demo does not do

- No real bank connection, no consent flow, no payment rails — `debit` moves a
  number in memory.
- Sterling only. `Denomination.all` is the whole catalogue; another currency
  means another list and the breakdown maths works unchanged.
- Nothing is persisted. Relaunching resets the wallet.
- Very large balances mean very many notes. A real build would bundle them
  above some count rather than simulating three hundred bodies.

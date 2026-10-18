# CashStack

A wallet that shows the money in your bank accounts as actual cash — Australian
notes and coins, in multiples, piled up and obeying gravity. Tip the phone and
the pile sloshes. To pay, you hold a note and swipe it off the top of the
screen, and your change falls back down.

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
| **Break it up** | Double tap a note or coin and it bursts into the fewest smaller pieces of the same value. A $100 becomes two $50s; a $50 becomes two $20s and a $10. The 5c has nothing to break into, so it just shakes its head. |
| **One account** | Link as many banks as you like, but the wallet holds one account's money at a time. Pick it from the accounts pill at the top; the pile swaps over to that balance, and that is the account the till takes payment from. |
| **Pay** | Tap **Pay at till** and the till rings something up by itself — no menu to choose from. The amount sits at the top and counts down as you hand money over. Press and hold a note, swipe it above the dashed line, let go. It's gone. |
| **Jars** | Pick up a coin and the header turns into three jars: **Invest**, **Donate**, **Save**. Drag the coin into one and let go. Let go anywhere else and it drops back in the pile. |
| **Tip jar** | At a café, a tip jar sits beside the amount while you pay, and stays on the receipt for a few seconds afterwards so some of your change can go straight in. |

Overpay and the figure at the top turns **green and goes negative** — that is
your change, and it sits there for a beat so you can read it before the payment
settles and the coins fall back in. Hand over more while it is negative and it
simply counts further down.

The pile is the source of truth, not a freshly-computed breakdown. Pay for a
$14.95 book with a $20 and you are genuinely carrying $5.05 of change
afterwards — a $5 and a 5c — until you tap **tidy** (the stack icon, bottom
left), which re-breaks the balance into the fewest possible pieces.

The top bar is glass and the physics world runs the full height of the screen
behind it, so a note swiped up to pay is still visible through the frosted bar
rather than disappearing under it. The bottom bar is solid and the pile lands on
its top edge, so nothing in the wallet is ever hidden.

## Spare change

Coins are the money nobody quite knows what to do with, so the wallet gives
them somewhere to go. Everything below works the same way as paying: hold a
piece, drag it somewhere, let go.

**The jars appear only when you pick up a coin.** The header swaps from your
balance to three big drop targets, dashed while they wait and solid black when
a coin is over one — the same armed look as the pay pill. Each jar says where
its money goes and how much has gone in this month, and the header says how much
of today's limit is left. A one-off hint under the header explains this until
the first coin goes in, because a feature that only appears on touch is
otherwise invisible.

**Nothing is chosen for you.** A jar with nowhere to send money still takes the
coin, then asks: "What should your $2 buy?" Pick a fund and the coin goes in;
tap **Put it back** and it falls back into the pile. After that, coins just
drop. Destinations can be changed any time under **Jars**.

| Jar | Where it goes | What actually happens |
|---|---|---|
| **Invest** | An ETF or a share you pick | Pooled and bought as fractional units at the next market open, so 5c buys a sliver. The picker carries a general-advice warning. |
| **Donate** | A charity you pick | Pooled and sent on the 1st as one gift, so it clears the $2 threshold for a tax-deductible receipt. |
| **Save** | One of your other linked accounts | Moved straight across. The account the wallet is paying from is never offered. |

**Every drop can be taken back.** A toast says what happened and what happens
next ("Buys at the next market open") with **Undo**, for eight seconds, and the
**Recent** list under **Jars** offers **Take back** for longer. Invested and
donated coins sit in a pool until the market opens or the 1st comes round, so
taking them back is honest.

**Guard rails, all in the Jars sheet.** Jars take **coins only** by default — a
$100 note in the wrong jar is a much worse mistake than a 20c coin, and a note
can be broken into coins with a double tap anyway. A **daily limit** across
jars ($10 by default) stops a fidgety thumb emptying the wallet; a coin over the
limit bounces back with a warning buzz and the jar says why. Each jar can be
switched off.

**Tipping is opt-in and never nags.** Only places that take tips put a jar out,
there are no suggested percentages and nothing is pre-filled. A tip goes **on
top of the bill**, never towards it, so the figure counting down is still the
bill; cancel the payment and the tip comes back too. After paying, the receipt
holds the tip jar out for eight seconds with a draining line and a close button,
because the real-world moment to tip is when the change lands. The countdown
pauses while a coin is in your hand, and with VoiceOver on it waits to be
closed. **Most I'll tip per payment** ($5 by default) caps it.

**Dragging is not the only way.** Tap either tip jar to pick a coin from a list,
and in the **Sorted** view every coin row has a menu that puts one in a jar. The
jar cards, tip jar and toast are all labelled for VoiceOver.

## How it is put together

```
CashStack/
  Model/Denomination.swift     Sterling denominations, sizes, and the breakdown maths
  Banking/BankDataSource.swift The protocol every bank conforms to, plus the demo source
  Banking/WalletStore.swift    Links accounts, holds the selected one's pile, settles payments
  Physics/CashScene.swift      SpriteKit world: gravity, walls, the pay line, drag-to-pay
  Physics/MoneyNode.swift      One note or coin as a physics body
  Physics/MotionManager.swift  CoreMotion gravity and shake, delivered by closure
  Banking/DemoTill.swift       The merchant side: a short menu, rung up at random
  SpareChange/SpareChange.swift  The jars, the funds and charities, the settings
  SpareChange/JarViews.swift     Jar header, tip jar, undo toast, first-run hint
  SpareChange/SpareChangeSheet.swift  Jars settings and the destination pickers
  Design/MoneyArt.swift        The notes and coins, drawn at runtime — no image assets
  Design/HoloShine.swift       The holographic shader
  Design/Fonts.swift           Registers Satoshi at launch
  Resources/Fonts/             Satoshi, five weights, with its licence
  Views/                       SwiftUI chrome, sorted view, accounts, till
```

**Design.** White ground, black hairlines at 1pt, Satoshi throughout, bright
money. The money is drawn big — a note is about half the screen wide — because
it is meant to be grabbed with a thumb, and every detail in `MoneyArt` is a
fraction of the note's height so the design holds together at any size. The notes and coins are drawn with CoreGraphics at launch and cached, so
there is nothing to redraw and nothing to ship.

**Type.** Satoshi ships in `Resources/Fonts` (Light, Regular, Medium, Bold,
Black) under the Fontshare free licence, which is included alongside it.
`Fonts.register()` registers the faces with CoreText at launch rather than
going through `UIAppFonts`, so they are available to SwiftUI, to the UIKit
navigation chrome, and to the CoreGraphics code that draws the money — with one
list of faces rather than two. `Theme` is the only place that names a font.

**The holographic shine** is a fragment shader on each piece of money
(`Design/HoloShine.swift`). A rainbow band sweeps diagonally on a slow loop,
staggered across four shader instances so the pieces do not all flash together,
and a second softer sheen tracks the device's roll — so the foil catches the
light as the handset moves. In the sorted view the SwiftUI thumbnails get the
same treatment with an animated gradient (`MoneyThumb` in
`Design/Components.swift`); the band is flattened with `compositingGroup()`
before being masked by the artwork, or the additive blend leaks past the note's
edges and the shine reads as a square sitting on top of the money.

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
    func credit(accountID: String, minor: Int) async throws
}
```

`WalletStore` holds an array of these and lists every account they return, so
linking another bank is just "add another source". Only the selected account
fills the pile and is debited when you pay. To go live, write one
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
a particular $100 note and swipe it to the top exactly as a person would. The
suite covers the balance breaking into the right notes and coins, the till
ringing up an amount by itself, the figure counting down and then going
negative, settling with change, cancelling and getting your money back, paying
from the sorted view, double tapping to break a note into smaller money, and
picking which single account fills the pile and pays.

Where the pile settles decides what is lying on top of what, so a test cannot
assume the piece it reaches for is the piece it gets. The payment tests pick
whichever piece is lying lowest on screen — clear of the glass header, where a
tap would land on the chrome instead — and then assert the arithmetic rather
than naming a note. The splitting test switches to an account holding a single
$100 so the piece under the thumb is not in doubt.

`CoinJarUITests` covers spare change: a jar asking where its money goes on the
first coin and going straight in after that, undo, notes kept out of the jars,
saving from the sorted view's menu, and a tip both while paying and from the
change. The app takes `-till "Pocket Coffee"` as a launch argument to pin the
till to a café, so there is always a tip jar to test against.

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
- Splitting stops at `Money.maxLoosePieces` (120). Without a cap, a determined
  thumb could turn a hundred dollars into two thousand 5c coins and the physics
  would grind to a halt.
- Australian dollars only. `Denomination.all` is the whole catalogue; another
  currency means another list and the breakdown maths works unchanged. Cash
  settles in 5c steps, since Australia withdrew the 1c and 2c — `Money.cashable`
  is what keeps the pile and the balance honest about that.
- Nothing is persisted. Relaunching resets the wallet, the jars and their
  settings.
- The funds and charities are made up, like the banks. Investing and donating
  stop at the pool: there is no broker or charity on the other end.
- Very large balances mean very many notes. A real build would bundle them
  above some count rather than simulating three hundred bodies.

# LUMI - Parent/Guardian Dashboard UI/UX Design Specification
## For Google Stitch UI Prototyping

---

## 1. DESIGN PHILOSOPHY

### Core Principles
- **Soft & Friendly**: Warm, approachable design that feels safe for families
- **Touch-First**: All interactions optimized for tap/swipe - no typing required
- **Minimal Cognitive Load**: Parents can log reading in under 30 seconds
- **Celebratory**: Every interaction reinforces positive reading habits
- **Child-Inclusive**: Children can participate in parts of the logging (emoji selection)

### Design Style Keywords
`Soft UI` `Neumorphism-lite` `Pastel` `Rounded` `Card-based` `Playful but Professional`

---

## 2. COLOR PALETTE

### Primary Colors
| Name | Hex | Usage |
|------|-----|-------|
| **Lumi Coral** | `#FF8698` | Primary accent, CTAs, streaks |
| **Lumi Peach** | `#FFAB91` | Progress rings, warm highlights |
| **Lumi Mint** | `#BCE7F0` | Success states, completed items |
| **Lumi Lavender** | `#D2EBBF` | Secondary accent, library books |

### Secondary Colors
| Name | Hex | Usage |
|------|-----|-------|
| **Sunny Yellow** | `#FFF6A4` | Achievements, celebrations |
| **Sky Blue** | `#90CAF9` | Decodable book indicators |
| **Soft Orange** | `#FFCC80` | Warnings, attention needed |
| **Sage Green** | `#A5D6A7` | Positive feedback, checkmarks |

### Neutral Colors
| Name | Hex | Usage |
|------|-----|-------|
| **Background** | `#F5F5F7` | App background (soft gray) |
| **Card White** | `#FFFFFF` | Card backgrounds |
| **Text Primary** | `#121211` | Headlines, primary text |
| **Text Secondary** | `#6B7280` | Subtitles, secondary info |
| **Divider** | `#E5E7EB` | Subtle separators |

### Semantic Colors
| State | Hex | Usage |
|-------|-----|-------|
| **Success** | `#4CAF50` | Checkmarks, completed |
| **Library Book** | `#81C784` | Green badge for library books |
| **Decodable Book** | `#64B5F6` | Blue badge for decodable books |

---

## 3. TYPOGRAPHY

### Font Family
**Primary**: `Nunito` (Google Font - rounded, friendly, highly legible)
**Fallback**: `SF Pro Rounded`, `system-ui`

### Type Scale
| Element | Size | Weight | Line Height |
|---------|------|--------|-------------|
| **Hero Number** | 72px | 800 (ExtraBold) | 1.0 |
| **H1 - Screen Title** | 28px | 700 (Bold) | 1.2 |
| **H2 - Card Title** | 22px | 700 (Bold) | 1.3 |
| **H3 - Section Label** | 18px | 600 (SemiBold) | 1.4 |
| **Body** | 16px | 400 (Regular) | 1.5 |
| **Body Small** | 14px | 400 (Regular) | 1.5 |
| **Caption** | 12px | 500 (Medium) | 1.4 |
| **Button** | 16px | 600 (SemiBold) | 1.0 |

---

## 4. SPACING & LAYOUT

### Spacing Scale (8px base)
| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4px | Tight spacing, inline elements |
| `sm` | 8px | Icon gaps, compact spacing |
| `md` | 16px | Standard padding, card gaps |
| `lg` | 24px | Section spacing |
| `xl` | 32px | Major section breaks |
| `2xl` | 48px | Screen-level padding top |

### Grid System
- **Columns**: 4
- **Margins**: 16px (left/right)
- **Gutter**: 12px
- **Max Content Width**: 428px (iPhone 14 Pro Max)

### Card Styling
```
Border Radius: 20px
Padding: 20px
Background: #FFFFFF
Shadow: 0 2px 8px rgba(0,0,0,0.04)
```

---

## 5. COMPONENTS

### 5.1 Navigation Bar (Bottom)
```
Height: 80px + safe area
Background: #FFFFFF
Shadow: 0 -2px 10px rgba(0,0,0,0.05)
Border Radius (top): 24px

Items: 4 icons
- Home (house icon) - active state: filled coral
- My Books (book stack icon)
- Awards (trophy/star icon)
- Settings (gear icon)

Active indicator: Filled icon + coral color (#FF8698)
Inactive: Outline icon + gray (#6B7280)
```

### 5.2 Primary Button (Log Reading CTA)
```
Height: 56px
Border Radius: 28px (pill shape)
Background: Linear gradient 135deg (#FF8698 → #FFAB91)
Text: White, 16px, SemiBold
Shadow: 0 4px 12px rgba(255,134,152,0.3)

Pressed state: Scale 0.98, shadow reduced
```

### 5.3 Book Card (Assigned Book List Item)
```
Height: 80px
Border Radius: 16px
Background: #FFFFFF
Padding: 12px

Layout:
[Book Cover Thumbnail 56x80] [16px gap] [Title + Type Badge stack]

Book Type Badge:
- Library: Mint green pill (#BCE7F0), "Library" text
- Decodable: Sky blue pill (#90CAF9), "Decodable" text
- Badge: 24px height, 12px horizontal padding, 12px border radius
```

### 5.4 Progress Ring (Multi-layer)
```
Inspired by reference image - concentric rings showing different metrics

Outer Ring: Total nights (coral/peach gradient)
Middle Ring: Current week progress (segmented, blue/yellow/green)
Inner Ring: Today's status (mint if complete, gray if pending)

Center: Large number + label
- Number: 72px, ExtraBold, #121211
- Label: 14px, Regular, #6B7280
```

### 5.5 Week Progress Bar (Horizontal)
```
7 circles in a row (M T W T F S S)
Circle size: 40px
Gap: 8px

States:
- Completed: Filled mint (#BCE7F0), checkmark icon
- Today (not done): Coral outline (#FF8698), pulsing
- Today (done): Filled coral with checkmark
- Future: Light gray fill (#E5E7EB)
- Missed: Unfilled with gray outline
```

### 5.6 Emoji Assessment Selector
```
5 emoji faces in a row (for child to tap)
Size: 48px each
Gap: 16px
Background (selected): Subtle colored halo matching emoji mood

Emojis (left to right):
😫 Frustrated (red halo when selected)
😕 Unsure (orange halo)
😐 Okay (yellow halo)
🙂 Good (light green halo)
😄 Great! (bright green halo)

Selected state: Scale 1.2, colored shadow/halo
```

### 5.7 Comment Chip (Pre-written Templates)
```
Height: 36px
Border Radius: 18px (pill)
Background: #F5F5F7
Border: 1px solid #E5E7EB
Padding: 0 16px
Text: 14px, Regular, #121211

Selected state:
- Background: #BCE7F0 (mint)
- Border: 1px solid #81C784
- Checkmark icon prepended
```

### 5.8 Stat Card (Streak/Milestone Display)
```
Height: 100px
Border Radius: 16px
Background: #FFFFFF
Padding: 16px

Layout: Vertical center
[Icon 32px - coral/yellow/pink themed]
[Number - 28px Bold]
[Label - 12px Caption gray]

3-column layout for: Current Streak | Best Streak | Total Nights
Dividers: 1px vertical line #E5E7EB
```

### 5.9 Confirmation Button
```
"I read with my child tonight" button

Full width minus margins
Height: 60px
Border Radius: 16px
Background: Gradient (#4CAF50 → #66BB6A)
Text: White, 16px SemiBold
Icon: Checkmark circle left of text

Pressed: Confetti animation triggers
```

---

## 6. SCREEN LAYOUTS

### 6.1 HOME SCREEN (Parent Dashboard)

```
┌─────────────────────────────────────┐
│  [Safe Area - Status Bar]           │
├─────────────────────────────────────┤
│                                     │
│  Hello, [Parent Name]!         🔔   │
│  [Child Name]'s Reading             │
│                                     │
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐    │
│  │     PROGRESS RING CARD      │    │
│  │                             │    │
│  │    ╭─────────────────╮      │    │
│  │    │   ◯ ◯ ◯ ◯ ◯    │      │    │
│  │    │  ╭───────────╮  │      │    │
│  │    │  │    47     │  │      │    │
│  │    │  │  nights   │  │      │    │
│  │    │  ╰───────────╯  │      │    │
│  │    ╰─────────────────╯      │    │
│  │                             │    │
│  │  🔥 12 day streak!          │    │
│  └─────────────────────────────┘    │
│                                     │
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐    │
│  │  This Week                  │    │
│  │                             │    │
│  │  (M) (T) (W) (T) (F) (S) (S)│    │
│  │   ✓   ✓   ✓   ✓   ○   ·   · │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
├─────────────────────────────────────┤
│  ┌─────────────────────────────┐    │
│  │  Tonight's Books            │    │
│  │                             │    │
│  │  ┌─────────────────────┐    │    │
│  │  │ 📚 │ The Big Pig    │    │    │
│  │  │    │ [Decodable]    │    │    │
│  │  └─────────────────────┘    │    │
│  │                             │    │
│  │  ┌─────────────────────┐    │    │
│  │  │ 📚 │ Dinosaur Story │    │    │
│  │  │    │ [Library]      │    │    │
│  │  └─────────────────────┘    │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │
│  │   ╭─────────────────────╮   │    │
│  │   │  📖 Log Reading     │   │    │
│  │   ╰─────────────────────╯   │    │
│  │                             │    │
│  └─────────────────────────────┘    │
│                                     │
├─────────────────────────────────────┤
│  [🏠]    [📚]    [🏆]    [⚙️]      │
│   Home   Books   Awards  Settings   │
└─────────────────────────────────────┘
```

### 6.2 LOG READING FLOW - Step 1: Select Book

```
┌─────────────────────────────────────┐
│  ←  Log Tonight's Reading           │
├─────────────────────────────────────┤
│                                     │
│  Which book did you read?           │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ ┌────┐                      │    │
│  │ │ 📖 │  The Big Pig         │ ○  │
│  │ │    │  [Decodable] 🔵      │    │
│  │ └────┘                      │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ ┌────┐                      │    │
│  │ │ 📖 │  Dinosaur Story      │ ○  │
│  │ │    │  [Library] 🟢        │    │
│  │ └────┘                      │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ ┌────┐                      │    │
│  │ │ 📖 │  Sam and the Cat     │ ◉  │
│  │ │    │  [Decodable] 🔵      │    │
│  │ └────┘                  ✓   │    │
│  └─────────────────────────────┘    │
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
│  ┌─────────────────────────────┐    │
│  │         Continue →          │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### 6.3 LOG READING FLOW - Step 2: Child Assessment

```
┌─────────────────────────────────────┐
│  ←  Log Tonight's Reading           │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │ 📖 Sam and the Cat          │    │
│  │    Decodable                │    │
│  └─────────────────────────────┘    │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  How did reading feel tonight?      │
│  (Let your child choose!)           │
│                                     │
│                                     │
│     😫    😕    😐    🙂    😄      │
│                                     │
│    Hard  Tricky  Okay  Good Great!  │
│                                     │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Selected: 🙂 Good                  │
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
│  ┌─────────────────────────────┐    │
│  │         Continue →          │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### 6.4 LOG READING FLOW - Step 3: Parent Comment (Optional)

```
┌─────────────────────────────────────┐
│  ←  Log Tonight's Reading           │
├─────────────────────────────────────┤
│                                     │
│  Add a comment (optional)           │
│  Tap phrases to build your note     │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  Encouragement                │   │
│  │                               │   │
│  │  ┌──────────────┐ ┌────────┐ │   │
│  │  │ Great job! ✓ │ │ Loved  │ │   │
│  │  └──────────────┘ │hearing │ │   │
│  │  ┌──────────────┐ │ you!   │ │   │
│  │  │ Keep it up!  │ └────────┘ │   │
│  │  └──────────────┘            │   │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  Reading Skills               │   │
│  │                               │   │
│  │  ┌────────────┐ ┌──────────┐ │   │
│  │  │ Sounded    │ │ Good     │ │   │
│  │  │ out words  │ │ finger   │ │   │
│  │  │ well ✓     │ │ tracking │ │   │
│  │  └────────────┘ └──────────┘ │   │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  Your comment:                │   │
│  │  "Great job! Sounded out      │   │
│  │   words well"                 │   │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │         Continue →          │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### 6.5 LOG READING FLOW - Step 4: Confirm

```
┌─────────────────────────────────────┐
│  ←  Log Tonight's Reading           │
├─────────────────────────────────────┤
│                                     │
│           ┌─────────┐               │
│           │  📖     │               │
│           │ Sam and │               │
│           │ the Cat │               │
│           └─────────┘               │
│                                     │
│        Tonight's Reading            │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  Book: Sam and the Cat      │    │
│  │  Type: Decodable            │    │
│  │  Feeling: 🙂 Good           │    │
│  │  Comment: Great job!        │    │
│  │           Sounded out words │    │
│  │           well              │    │
│  └─────────────────────────────┘    │
│                                     │
│                                     │
│                                     │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  ✓  I read with my child    │    │
│  │      tonight                │    │
│  └─────────────────────────────┘    │
│                                     │
│        Tap to complete              │
│                                     │
└─────────────────────────────────────┘
```

### 6.6 SUCCESS CELEBRATION SCREEN

```
┌─────────────────────────────────────┐
│                                     │
│           🎉 🎊 ✨ 🎉               │
│                                     │
│                                     │
│          ╭───────────────╮          │
│          │               │          │
│          │      ✓        │          │
│          │               │          │
│          ╰───────────────╯          │
│                                     │
│         Reading Logged!             │
│                                     │
│         Night 48 complete           │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  🔥 13        🏆 1          │    │
│  │  Day Streak   Badge Earned! │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  ⭐ Only 2 more nights to   │    │
│  │     reach 50 night award!   │    │
│  └─────────────────────────────┘    │
│                                     │
│                                     │
│  ┌─────────────────────────────┐    │
│  │         Done  🏠            │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### 6.7 AWARDS/BADGES SCREEN

```
┌─────────────────────────────────────┐
│           Awards & Badges           │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐    │
│  │     PROGRESS TO NEXT BADGE  │    │
│  │                             │    │
│  │    ╭─────────────────╮      │    │
│  │    │      48/50      │      │    │
│  │    │    ████████░░   │      │    │
│  │    │   nights        │      │    │
│  │    ╰─────────────────╯      │    │
│  │                             │    │
│  │    2 more to 50 Night Award │    │
│  └─────────────────────────────┘    │
│                                     │
│  Your Badges                        │
│                                     │
│  ┌───────┐ ┌───────┐ ┌───────┐     │
│  │  🌟   │ │  📚   │ │  🔥   │     │
│  │ First │ │  25   │ │  7    │     │
│  │ Night │ │Nights │ │ Day   │     │
│  └───────┘ └───────┘ └───────┘     │
│                                     │
│  ┌───────┐ ┌───────┐ ┌───────┐     │
│  │  🌈   │ │  ░░   │ │  ░░   │     │
│  │ Week  │ │  50   │ │  100  │     │
│  │Streak │ │Nights │ │Nights │     │
│  └───────┘ └───────┘ └───────┘     │
│             (locked)   (locked)     │
│                                     │
│  Milestones                         │
│  ════════════════════════════════   │
│  [25]───[50]───[75]───[100]──→      │
│   ✓      ○      ○       ○           │
│                                     │
├─────────────────────────────────────┤
│  [🏠]    [📚]    [🏆]    [⚙️]      │
└─────────────────────────────────────┘
```

### 6.8 MY BOOKS SCREEN

```
┌─────────────────────────────────────┐
│           My Books                  │
├─────────────────────────────────────┤
│                                     │
│  Currently Assigned (3)             │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ ┌────┐                      │    │
│  │ │ 📖 │  The Big Pig         │    │
│  │ │    │  [Decodable] 🔵      │    │
│  │ │    │  Assigned: Mon       │    │
│  │ └────┘                      │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ ┌────┐                      │    │
│  │ │ 📖 │  Dinosaur Story      │    │
│  │ │    │  [Library] 🟢        │    │
│  │ │    │  Assigned: Tue       │    │
│  │ └────┘                      │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ ┌────┐                      │    │
│  │ │ 📖 │  Sam and the Cat     │    │
│  │ │    │  [Decodable] 🔵      │    │
│  │ │    │  ✓ Read tonight      │    │
│  │ └────┘                      │    │
│  └─────────────────────────────┘    │
│                                     │
│  ─────────────────────────────────  │
│                                     │
│  Recently Completed                 │
│                                     │
│  ┌─────────────────────────────┐    │
│  │  📚 10 books this month     │    │
│  │      View history →         │    │
│  └─────────────────────────────┘    │
│                                     │
├─────────────────────────────────────┤
│  [🏠]    [📚]    [🏆]    [⚙️]      │
└─────────────────────────────────────┘
```

---

## 7. INTERACTION PATTERNS

### 7.1 Micro-interactions

**Button Press**
- Scale to 0.97 on touch
- Release with slight bounce (0.3s ease-out)
- Haptic feedback (light impact)

**Card Selection**
- Border color change to accent
- Checkmark appears with scale animation
- Background subtle tint

**Emoji Selection**
- Selected emoji scales to 1.3
- Colored halo/glow appears behind
- Other emojis slightly fade (0.7 opacity)
- Haptic feedback (selection tick)

**Streak Counter Update**
- Number rolls up animation
- Fire icon pulses/bounces
- Confetti particles if milestone

**Week Day Completion**
- Circle fills with mint color (radial wipe)
- Checkmark draws in (stroke animation)
- Subtle bounce

### 7.2 Transitions

**Screen-to-Screen**
- Slide left/right for flow progression
- Fade for tab switches
- Modal slides up from bottom

**Success Celebration**
- Confetti burst from center
- Checkmark circle draws in
- Stats cards stagger in from bottom

### 7.3 Loading States

- Skeleton screens with shimmer effect
- Use brand colors for shimmer (soft coral/mint)
- Never show spinners for < 300ms operations

---

## 8. ACCESSIBILITY

### Touch Targets
- Minimum 44x44pt for all interactive elements
- Emoji faces: 48pt minimum
- Buttons: Full width where possible

### Color Contrast
- All text meets WCAG AA (4.5:1 minimum)
- Interactive elements have non-color indicators (icons, borders)
- Book type badges use icons + color + text

### Screen Reader
- All images have alt text
- Buttons have descriptive labels
- Progress announced on completion

---

## 9. ILLUSTRATIONS & ICONS

### Character Mascot
- Consider friendly blob characters (like reference image)
- Soft, rounded shapes with simple faces
- Use for empty states, celebrations, onboarding
- Color palette matches brand (pastel coral, mint, lavender)

### Icon Style
- Rounded/soft line icons (2px stroke)
- Consistent with friendly aesthetic
- Filled variants for selected/active states

### Suggested Icon Set
- Home: House with heart
- Books: Stacked books
- Awards: Trophy or star badge
- Settings: Gear
- Checkmark: Rounded check in circle
- Streak: Flame
- Calendar: Simple calendar grid
- Notification: Bell

---

## 10. EMPTY STATES

### No Books Assigned
```
[Friendly blob character looking curious]

"No books yet!"

Your teacher will assign books soon.
Check back later! 📚
```

### First Time User
```
[Blob character waving]

"Welcome to Lumi!"

Ready to start your reading journey?
Your first book is waiting.

[Get Started →]
```

### Streak Lost
```
[Blob character with encouraging expression]

"Let's start fresh!"

Every reader has off days.
Ready to begin a new streak?

[Log Tonight's Reading]
```

---

## 11. SUMMARY FOR STITCH UI

### Key Visual Elements to Generate:
1. **Home dashboard** with progress ring, week tracker, book list
2. **Book selection cards** with cover thumbnails and type badges
3. **Emoji picker row** with selection states
4. **Comment chip builder** with tap-to-add phrases
5. **Confirmation screen** with summary card
6. **Success celebration** with confetti and stats
7. **Awards grid** with earned/locked badge states
8. **Bottom navigation** with 4 tabs

### Style Keywords for Prompting:
`soft pastel UI` `rounded corners` `card-based layout` `mobile app` `friendly children's app` `neumorphism lite` `coral and mint color scheme` `Nunito font` `progress rings` `achievement badges` `minimal shadows` `iOS style`

### Interaction Notes:
- All primary actions are single-tap
- No keyboard/typing required in main flow
- Child-friendly emoji picker
- Celebration animations on completion
- Progress always visible

---

*Document prepared for Google Stitch UI prototyping - January 2026*

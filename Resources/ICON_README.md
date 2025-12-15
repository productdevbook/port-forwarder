# App Icon Design

## Design Concept
A minimal network/connection themed icon designed for Port Forwarder.

### Visual Elements
- **Background**: Blue gradient (#4A90D9 → #2E5C8A), rounded square (Apple app icon style)
- **Center**: Large white circle (main connection node)
- **Three nodes**: 3 small white circles in triangle formation (representing port-forward connections)
- **Connection lines**: White lines connecting the central node to others

### SVG Code Explanation

```svg
<!-- Gradient background definition -->
<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
  <stop offset="0%" style="stop-color:#4A90D9"/>   <!-- Light blue -->
  <stop offset="100%" style="stop-color:#2E5C8A"/> <!-- Dark blue -->
</linearGradient>

<!-- Rounded corner square background -->
<rect width="1024" height="1024" rx="220" fill="url(#bg)"/>

<!-- Center node (r=80) -->
<circle cx="0" cy="0" r="80" fill="white"/>

<!-- Top node (r=60) -->
<circle cx="0" cy="-250" r="60" fill="white"/>

<!-- Bottom left node -->
<circle cx="-217" cy="125" r="60" fill="white"/>

<!-- Bottom right node -->
<circle cx="217" cy="125" r="60" fill="white"/>

<!-- Connection lines (stroke-width=24) -->
<line x1="0" y1="-70" x2="0" y2="-190" stroke="white" stroke-width="24"/>
...
```

## Converting SVG to ICNS

```bash
# 1. Convert SVG to PNG (1024x1024)
qlmanage -t -s 1024 -o . AppIcon.svg
mv AppIcon.svg.png icon_1024.png

# 2. Create iconset folder and resize
mkdir -p AppIcon.iconset
for size in 16 32 64 128 256 512; do
    sips -z $size $size icon_1024.png --out AppIcon.iconset/icon_${size}x${size}.png
    double=$((size * 2))
    sips -z $double $double icon_1024.png --out AppIcon.iconset/icon_${size}x${size}@2x.png
done

# 3. Create ICNS file
iconutil -c icns AppIcon.iconset -o AppIcon.icns

# 4. Cleanup
rm -rf AppIcon.iconset icon_1024.png
```

## Color Palette

| Usage | Color | Hex |
|-------|-------|-----|
| Gradient start | Light Blue | #4A90D9 |
| Gradient end | Dark Blue | #2E5C8A |
| Nodes and lines | White | #FFFFFF |

## Changing the Icon

1. Edit the `AppIcon.svg` file
2. Run the conversion commands above
3. Rebuild the app with `./scripts/build-app.sh`

---

## Creating Icons with AI

You can use the following prompts with ChatGPT, Claude, or similar AI tools to create professional SVG icons.

### General macOS/iOS App Icon Prompt

```
Create an SVG icon for a macOS app with these specifications:
- Size: 1024x1024 pixels
- Rounded rectangle background (rx="220" for Apple style corners)
- Use a gradient background (provide your colors)
- Simple, recognizable symbol in the center
- White or light colored iconography
- Minimal design, avoid too many details
- Output clean SVG code

App name: [YOUR APP NAME]
App purpose: [WHAT YOUR APP DOES]
Preferred colors: [YOUR COLOR PREFERENCES]
Symbol idea: [WHAT SYMBOL REPRESENTS YOUR APP]
```

### Example: For a Network/Connection App

```
Create an SVG icon for a macOS menu bar app called "Port Forwarder" that manages Kubernetes port-forward connections.

Specifications:
- 1024x1024 SVG
- Apple-style rounded square (rx=220)
- Blue gradient background (#4A90D9 to #2E5C8A, diagonal)
- White network symbol: central node connected to 3 outer nodes in triangle formation
- Clean, minimal design suitable for small menu bar display
- Modern, professional look

Output the complete SVG code.
```

### Prompt Templates for Different App Types

**Database/Storage App:**
```
Create SVG icon: 1024x1024, rounded corners (rx=220),
purple gradient (#8B5CF6 to #6D28D9),
white cylinder/database symbol with connection dots
```

**Security/Auth App:**
```
Create SVG icon: 1024x1024, rounded corners (rx=220),
green gradient (#10B981 to #059669),
white shield with checkmark symbol
```

**Developer Tools:**
```
Create SVG icon: 1024x1024, rounded corners (rx=220),
orange gradient (#F59E0B to #D97706),
white terminal/code brackets symbol
```

**Cloud/Sync App:**
```
Create SVG icon: 1024x1024, rounded corners (rx=220),
sky blue gradient (#0EA5E9 to #0284C7),
white cloud with sync arrows
```

### Basic SVG Structure

The SVG you get from AI should follow this structure:

```svg
<?xml version="1.0" encoding="UTF-8"?>
<svg width="1024" height="1024" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" style="stop-color:#COLOR1"/>
      <stop offset="100%" style="stop-color:#COLOR2"/>
    </linearGradient>
  </defs>

  <!-- Background -->
  <rect width="1024" height="1024" rx="220" fill="url(#bg)"/>

  <!-- Your icon content here -->
  <g transform="translate(512, 512)">
    <!-- Centered content -->
  </g>
</svg>
```

### Tips

1. **Keep it simple** - Should be recognizable even at small sizes (16x16, 32x32)
2. **Contrast** - Ensure sufficient contrast between background and icon colors
3. **Center alignment** - Use `transform="translate(512, 512)"` to center content
4. **Line thickness** - Use min 16-24px stroke to prevent disappearing at small sizes
5. **Test** - Test your created SVG at different sizes

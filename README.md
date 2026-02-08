
# Solitaire (Love2D) — Vim / Arrow Navigation Prototype

Controls
- Move cursor: h / j / k / l or Left / Down / Up / Right
- Select / Deselect: Space
- Move selected cards to target: Enter or m
- Draw from stock: Space when cursor over Stock
- Restart game: r
- Auto-move selected card to foundation (if legal): f
- Quit: Escape or window close

How to run
1. Install Love2D (https://love2d.org).
2. Save the files in a folder.
3. Run with: love path/to/folder

What this prototype includes
- Basic Klondike-like layout: Stock, Waste, 4 Foundations, 7 Tableau piles.
- Keyboard navigation with vim keys or arrow keys.
- Selection and moving of face-up card sequences from tableau, single-card moves to foundations.
- Simple rendering (no external assets).

Notes / Improvements
- This is a prototype focusing on navigation and core moves. Rules and visuals can be improved.
- Undo, scoring, and complete rule validation (e.g., multiple-card moves only when correctly alternating) are minimal but can be extended.
- Textures will be added at a later date

This project was made with contributions from GitHub Copilot AI

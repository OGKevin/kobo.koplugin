# Settings Menu Navigation

## Accessing Settings
1. Open KOReader file browser
2. Open the menu (top-left corner)
3. Select "Kobo Library" → Settings

## Settings Hierarchy
```
Kobo Library
├── Sync reading state with Kobo [Toggle]
├── Enable automatic sync on virtual library [Toggle]  
├── Sync reading state now [Action]
├── Sync behavior [Submenu]
│   ├── Enable sync FROM Kobo TO KOReader [Toggle]
│   ├── Enable sync FROM KOReader TO Kobo [Toggle]
│   ├── From Kobo to KOReader [Submenu]
│   │   ├── Sync from newer state (Current: Prompt)
│   │   └── Sync from older state (Current: Never)  
│   └── From KOReader to Kobo [Submenu]
│       ├── Sync to newer state (Current: Silent)
│       └── Sync to older state (Current: Never)
├── Refresh library [Action]
└── About [Info]
```

## Menu Item Reference

| Menu Item | Type | Function |
|-----------|------|----------|
| Sync reading state with Kobo | Toggle | Enable/disable all sync functionality |
| Enable automatic sync on virtual library | Toggle | Enable/disable automatic progress sync on library access (books are always displayed) |
| Sync reading state now | Action | Manually trigger progress sync for all books |
| Sync behavior | Submenu | Configure sync direction and behavior |
| Refresh library | Action | Refresh virtual library metadata |
| About | Info | Display plugin information |

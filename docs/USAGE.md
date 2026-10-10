# Clipori · Basic controls

[← Back to Clipori](../README.md)


| Action | Shortcut / entry point |
| --- | --- |
| Show or hide the shelf | `⇧⌘V`, or click the menu bar icon |
| Search | Start typing; `⌘F` returns to the search field |
| Hover over a card | Lift and highlight the card; does not select, copy, or paste |
| Select and copy a card | Click to select and replace the system clipboard with this card; the shelf stays open |
| Select with the keyboard | `↓`, then `← →`; press `⌘C` to copy |
| Select multiple / select a range | `⌘`-click / `⇧`-click; selects for categorizing without changing the clipboard |
| Categorize selected cards | Drag any selected card onto a category; or use Move to category in the context menu |
| Capture a screenshot | `⌃⇧⌘4` copies a selection to the system clipboard; Clipori captures it while recording is on |
| Preview an image | Select its card and press Space, or use Preview in the context menu |
| Paste into the previous app | Return, or double-click a card |
| Paste as plain text | `⇧↩` (text and links only; images use regular paste) |
| Quickly paste the first 9 entries | `⌘1`–`⌘9`; add `⇧` for plain text |
| Copy / preview / open a link | `⌘C` / Space / `⌘O` in the card area |
| Rename | `⌘R` |
| Edit / append | `⌘E`, or the card's context menu |
| Create a note | `⌘N`, or `+` in the upper-right corner |
| Delete / undo deletion | Delete / `⌘Z` in the card area |
| Switch categories / create a Pinboard | `⌘←`, `⌘→` / `⇧⌘N` |
| Pause or resume capture | `⌘T` |
| Search with AI | `⌘↩` after entering a question, or click the AI search button |
| Open settings | `⌘,`, or the settings button in the upper-right corner |

Record new combinations and check for conflicts in Settings → Shortcuts. Changes take effect when saved and persist across restarts. Text fields retain standard system actions such as copy and undo. Multi-selection batch pasting is not supported yet.

Direct pasting requires granting Clipori access in macOS Accessibility settings. Without access, Clipori still copies the selected content; switch back to the target app and press `⌘V` to paste. If a shortcut cannot be registered, the app displays a warning and remains accessible from the menu bar.

Image capture supports clipboard PNG, TIFF, and JPEG data, including screenshots copied with the Control modifier. Screenshots saved only as files are not captured automatically. Images keep their original pixel dimensions and transparency, and copy back as PNG/TIFF for apps that accept image pasting. Use Edit to add a title or searchable notes. Image text recognition and image iCloud sync are not included in this local Mac release; no image pixels are sent to AI. Images above 128 MB or 80 megapixels display an error instead of being saved.

The small card icon automatically indicates content type (text, link, image, or code). Its color follows the category; change category names and colors in Settings → Categories.

In Settings → Categories, drag a category row or its left handle to reorder it. The shelf tabs follow the same order, which is saved on this Mac. New categories appear at the end. Click Edit on a row to change its name, color, and pinboard status in place. Use the checkmark or Return to save, or the cross or Escape to cancel. The form below only creates new categories.

Click the color well to open the system color picker and choose any color or enter a hex value. Save the row to apply an existing category's color; new categories keep the chosen color when added.

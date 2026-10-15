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
| Daily notes | Daily notes on the shelf, or the menu bar icon's context menu |
| Delete / undo deletion | Delete / `⌘Z` in the card area |
| Switch categories / create a Pinboard | `⌘←`, `⌘→` / `⇧⌘N` |
| Pause or resume capture | `⌘T` |
| Search with AI | `⌘↩` after entering a question, or click the AI search button |
| Open settings | `⌘,`, or the settings button in the upper-right corner |

Record new combinations and check for conflicts in Settings → Shortcuts. Changes take effect when saved and persist across restarts. Text fields retain standard system actions such as copy and undo. Multi-selection batch pasting is not supported yet.

Direct pasting requires granting Clipori access in macOS Accessibility settings. Without access, Clipori still copies the selected content; switch back to the target app and press `⌘V` to paste. If a shortcut cannot be registered, the app displays a warning and remains accessible from the menu bar.

Clipori requests Accessibility access on the first direct paste. Declining stops automatic requests across launches; retry under Settings → General → Request Accessibility access. Enable Clipori yourself in System Settings; returning to the app rechecks access. Capturing copies or cuts and updating recency do not require this permission.

Text and link cards show a character count for the full body, including punctuation and excluding spaces, tabs, and line breaks. Combined emoji count as one character. Image cards show the stored PNG file size and pixel dimensions; the size can differ from the original JPEG/TIFF.

Copying exactly the same text or link again reuses the existing record without adding a card, keeping its title, category, pin status, and original creation date. Whitespace, line breaks, and case remain significant. Images are not deduplicated, and manually created notes remain independent. Existing duplicates from before the upgrade are not bulk-deleted. Newly cut/copied content refreshes the list immediately after capture, respecting existing search and category filters; duplicate captures do not trigger an incoming-record indicator.

Settings → General → Move to front after use is enabled by default. Repeated external copies or cuts reuse and promote the saved text record. Clicking a card, pressing `⌘C` in the card area, using its copy menu, or directly pasting through Clipori updates recency after successfully writing to the clipboard. Cards keep their positions in the current shelf; reopening applies the new order. Turning the setting off disables promotion for both duplicate captures and history usage. Ordering needs neither external paste detection nor Accessibility access; only direct paste needs that permission. Recency stays local and does not change creation dates, retention periods, or daily-note date attribution.

Cut and Copy use the same capture and deduplication rules, including `⌘X`, context-menu Cut, and cuts within Clipori's editor. Both are captured when they write to the system clipboard, subject to capture pause, ignored apps, and privacy markers. Monitoring continues during menu tracking and checks pending clipboard changes when switching apps, so quickly returning to the shelf does not discard a cut.

Image capture supports clipboard PNG, TIFF, and JPEG data, including screenshots copied with the Control modifier. Screenshots saved only as files are not captured automatically. Images keep their original pixel dimensions and transparency, and copy back as PNG/TIFF for apps that accept image pasting. Use Edit to add a title or searchable notes. Image text recognition and image iCloud sync are not included in this local Mac release; no image pixels are sent to AI. Images above 128 MB or 80 megapixels display an error instead of being saved.

The small card icon automatically indicates content type (text, link, image, or code). Its color follows the category; change category names and colors in Settings → Categories.

In Settings → Categories, drag a category row or its left handle to reorder it. The shelf tabs follow the same order, which is saved on this Mac. New categories appear at the end. Click Edit on a row to change its name, color, and pinboard status in place. Use the checkmark or Return to save, or the cross or Escape to cancel. The form below only creates new categories.

Click the color well to open the system color picker and choose any color or enter a hex value. Save the row to apply an existing category's color; new categories keep the chosen color when added.

In Settings → Data, click **Clear all memories…**, check the count and confirm. This deletes all text, images, notes, pinned items and items in pinboards, and closes open note windows. Categories, shortcuts and AI settings are kept. Clearing cannot be undone. With iCloud sync, the corresponding memories are also deleted from your other devices. New copies continue to be captured according to your settings.

## Daily notes

Open **Daily notes** from the shelf or the menu bar icon's context menu. Select today or a previous date in the sidebar. Edit items and subtasks in the two-column table, add notes or links, and check off individual subtasks. Items without subtasks have their own completion checkbox. Press Return in a subtask to add the next one. Reorder using drag handles or the ellipsis menus; deleted items can be immediately restored with **Undo deletion** in the footer.

Pin an item to carry it, including completed subtask progress, into each new day while it remains unfinished. When every subtask is complete, the item stays on its completion day and stops carrying forward the next day. Unpinning also stops future carryover without deleting existing content. Unpinned items stay on their original date.

The first visit creates today's page. After opening daily notes, Clipori checks for date changes while running, on wake and when reopening the window. Dates missed while the app was closed are filled in on the next visit using the same carryover rules. Dates follow the Mac's local time zone.

Each page is an independent snapshot. Checking off today's work never changes yesterday. Editing a historical page does not rewrite other existing pages. Changes save automatically; switching dates and closing wait for the latest edits to save. Failed saves keep the current draft available for retry.

### AI-assisted drafts

Configure your service, model and API key in **Settings → AI**. Select a date in daily notes and click **AI draft**. This uses text and link clipboard records still stored for that date, alongside the page's existing items. Generation runs on demand; opening a page does not upload anything. Images, image notes and ordinary manually created memories are excluded from clipboard sources. Existing items in the daily page are included to help avoid duplicates.

Edit suggestions if needed, then choose **Add selected**. New actions can be appended to existing items while keeping their titles, manual notes, pins and completion states. New items start unpinned and incomplete. Identically titled completed subtasks are not added again. Expand **Clipboard sources** in a suggestion or saved item to inspect locally verified excerpts. Valid citations do not guarantee correct AI interpretation; adjust suggestions before accepting them.

Copied duplicates are combined locally. Each request reads up to the 200 most recent eligible records, with a total body budget of 32,000 characters and 2,400 per record. The interface indicates clipping. Clipboard records already removed by cleanup cannot be analyzed, but saved daily notes and their excerpts remain. Errors or cancellation leave your notes unchanged; retry or continue writing manually.

Choose **Add to daily notes** from a card's context menu to add its title and text to today's page. Daily notes are currently local to the Mac, stored in `daily-notes.sqlite` in the data folder. Clipboard retention and **Clear all memories** do not delete daily notes, and iCloud sync does not include them yet.

### AI classification scope

Auto-classification handles only records newly captured locally while it is enabled and AI is configured. Launching, syncing, editing, copying duplicates, enabling the toggle, or saving settings never scans history. Failed or unmatched records remain uncategorized without automatic retries.

To process history, choose Settings → AI → Classify uncategorized records. This uses saved AI settings independently of the automatic toggle, taking a snapshot of currently uncategorized records, including previous AI attempts with no match. Manual assignments, including explicit unclassified choices, are preserved. The UI shows the pending count and batch progress. Stop cancels queued classification, including automatic work, while keeping completed results; future captures still follow the automatic toggle. Images without text are skipped, and only titles or text notes are sent for images. Classification chooses existing regular categories without creating categories or using pinboards.

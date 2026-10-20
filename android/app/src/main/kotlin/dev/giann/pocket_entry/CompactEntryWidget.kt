package dev.giann.pocket_entry

/** A separate provider keeps existing larger home widgets unchanged. */
class CompactEntryWidget : QuickEntryWidget() {
    override val compact = true
}

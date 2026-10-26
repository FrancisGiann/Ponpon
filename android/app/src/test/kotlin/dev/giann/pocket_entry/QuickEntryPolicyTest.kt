package dev.giann.pocket_entry

import org.junit.Assert.*
import org.junit.Test

class QuickEntryPolicyTest {
    @Test fun shortcutOpensOnlyAnUnselectedDraft() {
        assertEquals(QuickEntryPolicy.Route(null, null), QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, null))
        assertNull(QuickEntryPolicy.parse("android.intent.action.VIEW", "pocketentry://quick/food"))
    }
    @Test fun categoriesAndWidgetIdentityAreValidated() {
        assertEquals(QuickEntryPolicy.Route("food", 12), QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, "pocketentry://quick/food?widget=12"))
        for (uri in listOf("https://quick/food", "pocketentry://other/food", "pocketentry://quick/../food", "pocketentry://quick/food/bills", "pocketentry://quick/food?wallet=gcash", "pocketentry://quick/food?amount=500", "pocketentry://quick/food?widget=0", "pocketentry://quick/food?widget=-1", "pocketentry://quick/food?widget=12&amount=5", "pocketentry://user@quick/food", "pocketentry://quick:99/food", "pocketentry://quick/food#save", "pocketentry://quick/food?widget=9999999999")) {
            assertNull(uri, QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, uri))
        }
    }
    @Test fun kindAndWalletRoutesRequireValidPathsAndWidgetIds() {
        assertEquals("income", QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, "pocketentry://kind/income?widget=3")?.kind)
        assertEquals("expense", QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, "pocketentry://kind/expense?widget=3")?.kind)
        assertEquals("cash", QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, "pocketentry://wallet/cash?widget=3")?.walletId)
        for (uri in listOf("pocketentry://kind/transfer?widget=3", "pocketentry://wallet/cash?widget=0", "pocketentry://wallet/cash?amount=1")) {
            assertNull(QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, uri))
        }
    }
    @Test fun wideCategoryRoutesCarryKindWithoutAmountOrWallet() {
        assertEquals(QuickEntryPolicy.Route("food", 8, kind = "expense"),
            QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, "pocketentry://wide/expense/food?widget=8"))
        assertEquals(QuickEntryPolicy.Route("income_allowance", 8, kind = "income"),
            QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, "pocketentry://wide/income/income_allowance?widget=8"))
        for (uri in listOf("pocketentry://wide/transfer/food?widget=8", "pocketentry://wide/income/food/extra?widget=8", "pocketentry://wide/income/food?wallet=cash", "pocketentry://wide/income/food?widget=0")) {
            assertNull(QuickEntryPolicy.parse(QuickEntryPolicy.ACTION, uri))
        }
    }
}

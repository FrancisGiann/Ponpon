package dev.giann.pocket_entry

import android.content.Context
import android.content.res.Configuration
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SchoolCategoryWidgetTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    private val categories = "[{\"id\":\"school_supplies\",\"name\":\"School supplies\",\"icon\":\"school\"},{\"id\":\"food\",\"name\":\"Food\",\"icon\":\"food\"},{\"id\":\"travel\",\"name\":\"Travel\",\"icon\":\"travel\"},{\"id\":\"bills\",\"name\":\"Bills\",\"icon\":\"bills\"}]"

    @Test fun schoolUsesItsBookPictogramAndExplicitCategoryRoute() {
        assertNotEquals(QuickEntryWidget.iconResource("other", false), QuickEntryWidget.iconResource("school", false))
        assertNotEquals(QuickEntryWidget.iconResource("school", false), QuickEntryWidget.iconResource("school", true))
        assertEquals("blue", QuickEntryWidget.categoryTone("school"))
        for (theme in listOf("light", "dark")) {
            context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit()
                .putString("theme", theme).putString("categories", categories).commit()
            val view = QuickEntryWidget.views(context, 610).apply(context, FrameLayout(context))
            assertEquals("School supplies", view.findViewById<TextView>(R.id.category_one_name).text.toString())
            assertNotNull(view.findViewById<ImageView>(R.id.category_one_icon).drawable)
            val cell = view.findViewById<View>(R.id.category_one)
            assertEquals("Add School supplies entry", cell.contentDescription)
            assertTrue(cell.performClick())
            val intent = Shadows.shadowOf(RuntimeEnvironment.getApplication()).nextStartedActivity
            assertEquals("school_supplies", QuickEntryPolicy.parse(intent.action, intent.dataString)?.categoryId)
            assertFalse(intent.hasExtra("wallet")); assertFalse(intent.hasExtra("amount"))
        }
    }

    @Test fun compactSchoolKeepsItsFullAccessibleNameAndMinimumTarget() {
        val original = Configuration(context.resources.configuration)
        try {
            for (scale in listOf(1f, 1.5f)) for (theme in listOf("light", "dark")) {
                val config = Configuration(original); config.fontScale = scale
                @Suppress("DEPRECATION")
                context.resources.updateConfiguration(config, context.resources.displayMetrics)
                context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit()
                    .putString("theme", theme).putString("categories", categories).commit()
                for (width in listOf(128, 148, 180)) {
                    val view = QuickEntryWidget.views(context, 611, true).apply(context, FrameLayout(context))
                    view.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY))
                    view.layout(0, 0, width, width)
                    val cell = view.findViewById<View>(R.id.category_one)
                    val label = view.findViewById<TextView>(R.id.category_one_name)
                    assertTrue(cell.isClickable && cell.height >= 48 && cell.width >= 48)
                    assertEquals("School", label.text.toString())
                    assertEquals("Add School supplies entry", cell.contentDescription)
                    assertTrue(label.bottom <= cell.height)
                    assertTrue(label.layout.getLineBottom(0) <= label.height)
                    assertNotNull(view.findViewById<ImageView>(R.id.category_one_icon).drawable)
                }
            }
        } finally {
            @Suppress("DEPRECATION")
            context.resources.updateConfiguration(original, context.resources.displayMetrics)
        }
    }
}

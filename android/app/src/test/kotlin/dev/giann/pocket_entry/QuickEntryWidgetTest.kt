package dev.giann.pocket_entry

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import android.widget.ImageView
import android.content.pm.ActivityInfo
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.Shadows
import java.io.File

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class QuickEntryWidgetTest {
    private val context: Context get() = RuntimeEnvironment.getApplication()
    @Test fun eachWidgetAndCategoryHasItsOwnImmutableExplicitIntent() {
        val one = QuickEntryWidget.pending(context, 101, 1, "food")
        val two = QuickEntryWidget.pending(context, 102, 1, "food")
        val other = QuickEntryWidget.pending(context, 101, 2, "travel")
        assertNotEquals(one, two); assertNotEquals(one, other)
        assertTrue(one.isImmutable)
        val intent = Shadows.shadowOf(one).savedIntent
        assertEquals(ComponentName(context, MainActivity::class.java), intent.component)
        assertEquals(QuickEntryPolicy.ACTION, intent.action)
        assertEquals("pocketentry://quick/food?widget=101", intent.dataString)
        assertFalse(intent.hasExtra("amount")); assertFalse(intent.hasExtra("wallet"))
    }
    @Test fun receiverIsPrivateAndOnlyFourCategoriesAreRendered() {
        val info = context.packageManager.getReceiverInfo(ComponentName(context, QuickEntryWidget::class.java), PackageManager.GET_META_DATA)
        assertFalse(info.exported)
        val view = QuickEntryWidget.views(context, 1).apply(context, FrameLayout(context))
        assertEquals("Food", view.findViewById<TextView>(R.id.category_one_name).text.toString())
        assertEquals("Shopping", view.findViewById<TextView>(R.id.category_four_name).text.toString())
        assertFalse(allText(view).contains("₱")); assertFalse(allText(view).contains("balance", true))
    }
    @Test fun staleSlotsDisappearWhenCategorySelectionChanges() {
        context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit().putString("categories", "[{\"id\":\"travel\",\"name\":\"Travel\"}]").commit()
        val view = QuickEntryWidget.views(context, 2).apply(context, FrameLayout(context))
        assertEquals("Travel", view.findViewById<TextView>(R.id.category_one_name).text.toString())
        assertEquals(View.GONE, view.findViewById<View>(R.id.category_two).visibility)
        assertEquals(View.GONE, view.findViewById<View>(R.id.category_four).visibility)
    }
    @Test fun actualAndroidRemoteViewsRenderLightAndDarkPreviews() {
        for (theme in listOf("light", "dark")) {
            context.getSharedPreferences(QuickEntryWidget.PREFS, Context.MODE_PRIVATE).edit().putString("theme", theme).putString("categories", QuickEntryWidget.defaultCategories).commit()
            val view = QuickEntryWidget.views(context, 200).apply(context, FrameLayout(context))
            view.measure(View.MeasureSpec.makeMeasureSpec(330, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(180, View.MeasureSpec.EXACTLY))
            view.layout(0, 0, 330, 180)
            for (slot in QuickEntryWidget.slots) assertTrue(view.findViewById<View>(slot).height >= 48)
            val bitmap = Bitmap.createBitmap(660, 360, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap); canvas.scale(2f, 2f); view.draw(canvas)
            val directory = File(requireNotNull(System.getProperty("pocket.previewDir"))); directory.mkdirs()
            File(directory, "widget-native-$theme.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            assertTrue(File(directory, "widget-native-$theme.png").length() > 1000)
        }
    }
    @Test fun resizedNativeRowsFillTallAndCompactHostsWithIconsAndNoPrivateData() {
        val sizes=listOf(220 to 180,330 to 270,330 to 360,520 to 180)
        for(theme in listOf("light","dark")) for((width,height) in sizes) {
            context.getSharedPreferences(QuickEntryWidget.PREFS,Context.MODE_PRIVATE).edit().putString("theme",theme).putString("categories",QuickEntryWidget.defaultCategories).commit()
            val view=QuickEntryWidget.views(context,301).apply(context,FrameLayout(context))
            view.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(height,View.MeasureSpec.EXACTLY))
            view.layout(0,0,width,height)
            val grid=view.findViewById<View>(R.id.category_grid)
            assertEquals(height-12,grid.bottom)
            for(i in QuickEntryWidget.slots.indices){
                val cell=view.findViewById<View>(QuickEntryWidget.slots[i])
                assertTrue(cell.height>=48);assertTrue(cell.width>=48)
                assertTrue(cell.isClickable)
                assertTrue(cell.contentDescription.startsWith("Add "))
                assertNotNull(view.findViewById<ImageView>(QuickEntryWidget.icons[i]).drawable)
            }
            val second=view.findViewById<View>(R.id.widget_row_2)
            assertEquals(grid.height,second.bottom)
            assertFalse(allText(view).contains("₱"));assertFalse(allText(view).contains("balance",true))
            val bitmap=Bitmap.createBitmap(width*2,height*2,Bitmap.Config.ARGB_8888)
            val canvas=Canvas(bitmap);canvas.scale(2f,2f);view.draw(canvas)
            val directory=File(requireNotNull(System.getProperty("pocket.previewDir")));directory.mkdirs()
            File(directory,"widget-native-${width}x${height}-$theme.png").outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
        }
    }
    @Test fun categoryPictogramsFollowUserSelectionAndActivityHasSingleInstance() {
        assertNotEquals(QuickEntryWidget.iconResource("food",false),QuickEntryWidget.iconResource("health",false))
        assertNotEquals(QuickEntryWidget.iconResource("health",false),QuickEntryWidget.iconResource("health",true))
        assertEquals(QuickEntryWidget.iconResource("other",false),QuickEntryWidget.iconResource("unknown",false))
        val info=context.packageManager.getActivityInfo(ComponentName(context,MainActivity::class.java),0)
        assertEquals(ActivityInfo.LAUNCH_SINGLE_TASK,info.launchMode)
    }
    @Test fun emptyWidgetHasOneFullAreaAccessibleQuickAdd() {
        context.getSharedPreferences(QuickEntryWidget.PREFS,Context.MODE_PRIVATE).edit().putString("categories","[]").commit()
        val view=QuickEntryWidget.views(context,400).apply(context,FrameLayout(context))
        view.measure(View.MeasureSpec.makeMeasureSpec(330,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(270,View.MeasureSpec.EXACTLY));view.layout(0,0,330,270)
        assertEquals(View.GONE,view.findViewById<View>(R.id.category_grid).visibility)
        val add=view.findViewById<View>(R.id.widget_empty_add)
        assertEquals(View.VISIBLE,add.visibility);assertTrue(add.isClickable);assertTrue(add.height>=48)
        assertEquals(270-12,add.bottom);assertEquals("Add an entry",add.contentDescription)
        assertFalse(allText(view).contains("₱"))
    }
    @Test fun largeTypeNativeCategoryTextFitsCompactAndTallCells() {
        val original=android.content.res.Configuration(context.resources.configuration)
        val scaled=android.content.res.Configuration(original);scaled.fontScale=1.5f
        @Suppress("DEPRECATION")
        context.resources.updateConfiguration(scaled,context.resources.displayMetrics)
        try {
            context.getSharedPreferences(QuickEntryWidget.PREFS,Context.MODE_PRIVATE).edit().putString("categories",QuickEntryWidget.defaultCategories).commit()
            for((width,height) in listOf(220 to 180,330 to 270)) {
                val view=QuickEntryWidget.views(context,500).apply(context,FrameLayout(context))
                view.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(height,View.MeasureSpec.EXACTLY));view.layout(0,0,width,height)
                for(i in QuickEntryWidget.slots.indices){
                    val cell=view.findViewById<View>(QuickEntryWidget.slots[i]);val label=view.findViewById<TextView>(QuickEntryWidget.labels[i])
                    assertTrue("Category label clipped at 1.5x type",label.bottom<=cell.height)
                    assertTrue("Text line needs more height than its view",label.layout.getLineBottom(0)<=label.height-label.paddingTop-label.paddingBottom)
                    assertTrue(cell.height>=48)
                }
                val bitmap=Bitmap.createBitmap(width*2,height*2,Bitmap.Config.ARGB_8888)
                val canvas=Canvas(bitmap);canvas.scale(2f,2f);view.draw(canvas)
                val directory=File(requireNotNull(System.getProperty("pocket.previewDir")));directory.mkdirs()
                File(directory,"widget-native-${width}x${height}-large-type.png").outputStream().use{bitmap.compress(Bitmap.CompressFormat.PNG,100,it)}
            }
        } finally {
            @Suppress("DEPRECATION")
            context.resources.updateConfiguration(original,context.resources.displayMetrics)
        }
    }
    @Test fun actualLauncherIconIsRenderedWithoutChangingAssets() {
        val info = context.packageManager.getApplicationInfo(context.packageName, 0)
        assertEquals(R.mipmap.ponpon_launcher, info.icon)
        val drawable = context.getDrawable(info.icon)!!
        val bitmap = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, 512, 512); drawable.draw(Canvas(bitmap))
        val directory = File(requireNotNull(System.getProperty("pocket.previewDir"))); directory.mkdirs()
        File(directory, "current-launcher-icon.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        assertTrue(File(directory, "current-launcher-icon.png").length() > 1000)
    }
    @Test fun walletLauncherUsesVectorsAndOffersAMonochromeLayer() {
        val drawable = context.getDrawable(R.mipmap.ponpon_launcher) as android.graphics.drawable.AdaptiveIconDrawable
        assertTrue(drawable.foreground is android.graphics.drawable.VectorDrawable)
        assertNotNull(drawable.monochrome)
        for (size in listOf(48, 96, 192)) {
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            drawable.setBounds(0, 0, size, size); drawable.draw(Canvas(bitmap))
            assertNotEquals(bitmap.getPixel(size / 2, size / 2), bitmap.getPixel(size / 2, size / 8))
        }
        val mono = requireNotNull(drawable.monochrome)
        val bitmap = Bitmap.createBitmap(512, 512, Bitmap.Config.ARGB_8888)
        mono.setBounds(0, 0, 512, 512); mono.draw(Canvas(bitmap))
        val directory = File(requireNotNull(System.getProperty("pocket.previewDir"))); directory.mkdirs()
        File(directory, "wallet-icon-monochrome-023.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
    private fun allText(view: View): String = if (view is TextView) view.text.toString() else if (view is android.view.ViewGroup) (0 until view.childCount).joinToString(" ") { allText(view.getChildAt(it)) } else ""
}

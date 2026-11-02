package hu.fogmosas.wear

import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DimensionBuilders.expand
import androidx.wear.protolayout.DimensionBuilders.sp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import hu.fogmosas.shared.AppStore
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

/** Wear OS tile: today's brushings and the streak; tap opens the app. */
class ProgressTileService : TileService() {
    private val version = "1"

    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> =
        CallbackToFutureAdapter.getFuture { c ->
            c.set(tile())
            "tile"
        }

    override fun onTileResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> =
        CallbackToFutureAdapter.getFuture { c ->
            c.set(ResourceBuilders.Resources.Builder().setVersion(version).build())
            "resources"
        }

    private fun text(s: String, size: Float, color: Int = 0xFFFFFFFF.toInt(), bold: Boolean = false) =
        LayoutElementBuilders.Text.Builder().setText(s).setFontStyle(
            LayoutElementBuilders.FontStyle.Builder().setSize(sp(size)).setColor(argb(color))
                .setWeight(if (bold) LayoutElementBuilders.FONT_WEIGHT_BOLD else LayoutElementBuilders.FONT_WEIGHT_NORMAL).build(),
        ).build()

    private fun tile(): TileBuilders.Tile {
        val store = AppStore.get(this)
        val d = store.data.value
        val goals = d.profile("me")?.goals ?: d.activeProfile.goals
        val rs = d.records("me")
        val today = LocalDate.now()
        val count = store.coach.todayCount(rs, today)
        val streak = store.coach.perfectStreak(rs, goals, today)
        val done = count >= goals.perDay

        val open = ModifiersBuilders.Clickable.Builder().setId("open").setOnClick(
            ActionBuilders.LaunchAction.Builder().setAndroidActivity(
                ActionBuilders.AndroidActivity.Builder().setPackageName(packageName).setClassName(WearActivity::class.java.name).build(),
            ).build(),
        ).build()

        val column = LayoutElementBuilders.Column.Builder()
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(text(if (done) "🎉" else "🪥", 28f))
            .addContent(text("Ma $count/${goals.perDay}", 22f, bold = true))
            .addContent(text("🔥 $streak nap", 14f, 0xFFB8C7CF.toInt()))
            .addContent(text(if (done) "Mára kész!" else "Koppints az indításhoz", 12f, 0xFF57C5B6.toInt()))
            .build()

        val root = LayoutElementBuilders.Box.Builder()
            .setWidth(expand()).setHeight(expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setModifiers(ModifiersBuilders.Modifiers.Builder().setClickable(open).build())
            .addContent(column)
            .build()

        // Refresh at midnight, when the count starts again from 0.
        val midnight = LocalDateTime.of(today.plusDays(1), java.time.LocalTime.MIDNIGHT).atZone(ZoneId.systemDefault()).toInstant().toEpochMilli()
        return TileBuilders.Tile.Builder()
            .setResourcesVersion(version)
            .setTileTimeline(TimelineBuilders.Timeline.fromLayoutElement(root))
            .setFreshnessIntervalMillis(maxOf(midnight - System.currentTimeMillis(), 60_000L))
            .build()
    }
}

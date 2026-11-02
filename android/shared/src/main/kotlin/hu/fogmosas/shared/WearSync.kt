package hu.fogmosas.shared

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import hu.fogmosas.core.BrushRecord
import hu.fogmosas.core.Goals

/** Phone <-> watch via the Wearable Data Layer (both apps share the package name and signing key). */
object WearSync {
    const val PATH_RECORD = "/brush-record"
    const val PATH_GOALS = "/goals"

    fun sendRecord(ctx: Context, record: BrushRecord) {
        val bytes = AppStore.json.encodeToString(BrushRecord.serializer(), record).toByteArray()
        Wearable.getNodeClient(ctx).connectedNodes.addOnSuccessListener { nodes ->
            for (n in nodes) Wearable.getMessageClient(ctx).sendMessage(n.id, PATH_RECORD, bytes)
        }
    }

    fun decodeRecord(bytes: ByteArray): BrushRecord? =
        runCatching { AppStore.json.decodeFromString(BrushRecord.serializer(), String(bytes)) }.getOrNull()

    fun pushGoals(ctx: Context, goals: Goals) {
        val req = PutDataMapRequest.create(PATH_GOALS).apply {
            dataMap.putInt("perDay", goals.perDay)
            dataMap.putDouble("targetS", goals.targetS)
            dataMap.putLong("ts", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(ctx).putDataItem(req)
    }
}

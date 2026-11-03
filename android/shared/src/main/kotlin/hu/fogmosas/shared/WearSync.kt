package hu.fogmosas.shared

import android.content.Context
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import hu.fogmosas.core.BrushRecord
import hu.fogmosas.core.CareEntry
import hu.fogmosas.core.Goals

/** Phone <-> watch via the Wearable Data Layer (both apps share the package name and signing key). */
object WearSync {
    const val PATH_RECORD = "/brush-record"
    const val PATH_GOALS = "/goals"
    const val PATH_CARE = "/care-entry"

    fun sendCare(ctx: Context, entry: CareEntry) {
        val bytes = AppStore.json.encodeToString(CareEntry.serializer(), entry).toByteArray()
        Wearable.getNodeClient(ctx).connectedNodes.addOnSuccessListener { nodes ->
            for (n in nodes) Wearable.getMessageClient(ctx).sendMessage(n.id, PATH_CARE, bytes)
        }
    }

    fun decodeCare(bytes: ByteArray): CareEntry? =
        runCatching { AppStore.json.decodeFromString(CareEntry.serializer(), String(bytes)) }.getOrNull()

    fun sendRecord(ctx: Context, record: BrushRecord) {
        val bytes = AppStore.json.encodeToString(BrushRecord.serializer(), record).toByteArray()
        Wearable.getNodeClient(ctx).connectedNodes.addOnSuccessListener { nodes ->
            for (n in nodes) Wearable.getMessageClient(ctx).sendMessage(n.id, PATH_RECORD, bytes)
        }
    }

    fun decodeRecord(bytes: ByteArray): BrushRecord? =
        runCatching { AppStore.json.decodeFromString(BrushRecord.serializer(), String(bytes)) }.getOrNull()

    fun pushGoals(ctx: Context, goals: Goals, brushHand: String = AppStore.get(ctx).data.value.profile("me")?.brushHand ?: "right",
                  watchWrist: String = AppStore.get(ctx).data.value.profile("me")?.watchWrist ?: "left") {
        val req = PutDataMapRequest.create(PATH_GOALS).apply {
            dataMap.putInt("perDay", goals.perDay)
            dataMap.putDouble("targetS", goals.targetS)
            dataMap.putString("brushHand", brushHand)
            dataMap.putString("watchWrist", watchWrist)
            dataMap.putLong("ts", System.currentTimeMillis())
        }.asPutDataRequest().setUrgent()
        Wearable.getDataClient(ctx).putDataItem(req)
    }
}

package hu.fogmosas.app

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import hu.fogmosas.core.Quadrants

object C {
    val brand = Color(0xFF1E9BB8)
    val brand2 = Color(0xFF57C5B6)
    val warn = Color(0xFFE8833A)
    val danger = Color(0xFFD9534F)
    val ok = Color(0xFF2E9E6A)
    val bg = Color(0xFFF2F6F8)
    val kidTop = Color(0xFFFFF6D6)
    val kidBottom = Color(0xFFFFE3EC)
    val track = Color(0xFFDFE9EF)
    val muted = Color(0xFF5B6D79)
}

@Composable
fun FogmosasTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = lightColorScheme(primary = C.brand, secondary = C.brand2, background = C.bg), content = content)
}

val kidBrush = Brush.verticalGradient(listOf(C.kidTop, C.kidBottom))

@Composable
fun InfoCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier.fillMaxWidth(), shape = RoundedCornerShape(18.dp), colors = CardDefaults.cardColors(containerColor = Color.White)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp), content = content)
    }
}

@Composable
fun AvatarCircle(emoji: String, size: Dp = 54.dp, selected: Boolean = false, onClick: (() -> Unit)? = null) {
    Box(
        Modifier.size(size).clip(CircleShape).background(Color.White)
            .border(BorderStroke(3.dp, if (selected) C.brand else Color.Transparent), CircleShape)
            .let { if (onClick != null) it.clickable { onClick() } else it },
        contentAlignment = Alignment.Center,
    ) { Text(emoji, fontSize = (size.value * 0.55f).sp) }
}

@Composable
fun ProgressRing(fraction: Double, label: String, sub: String, color: Color = C.brand, size: Dp = 220.dp) {
    Box(contentAlignment = Alignment.Center, modifier = Modifier.size(size)) {
        CircularProgressIndicator(progress = { 1f }, modifier = Modifier.size(size), color = C.track, strokeWidth = size * 0.09f)
        CircularProgressIndicator(progress = { fraction.toFloat().coerceIn(0.001f, 1f) }, modifier = Modifier.size(size),
            color = color, strokeWidth = size * 0.09f, strokeCap = StrokeCap.Round, trackColor = Color.Transparent)
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(label, fontSize = (size.value * 0.2f).sp, fontWeight = FontWeight.ExtraBold)
            Text(sub, color = C.muted)
        }
    }
}

@Composable
fun QuadrantGrid(current: Int, labels: Boolean = true) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (row in 0..1) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (col in 0..1) {
                val i = row * 2 + col
                val c = when {
                    i + 1 < current -> C.brand2
                    i + 1 == current -> C.brand
                    else -> C.track
                }
                Box(Modifier.size(width = 72.dp, height = 30.dp).clip(RoundedCornerShape(8.dp)).background(c), contentAlignment = Alignment.Center) {
                    if (labels) Text(Quadrants.names[i], fontSize = 10.sp, fontWeight = FontWeight.Bold, color = if (i + 1 <= current) Color.White else C.muted)
                }
            }
        }
    }
}

@Composable
fun Banner(text: String, color: Color) {
    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(color.copy(alpha = 0.12f)).padding(12.dp)) {
        Text(text, color = color, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun BigButton(text: String, onClick: () -> Unit) {
    Box(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp))
            .background(Brush.linearGradient(listOf(C.brand, C.brand2))).clickable { onClick() }.padding(vertical = 22.dp),
        contentAlignment = Alignment.Center,
    ) { Text(text, color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold) }
}

@Composable
fun VSpace(h: Int) = Spacer(Modifier.height(h.dp))

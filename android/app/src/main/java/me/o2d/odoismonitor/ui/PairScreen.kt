package me.o2d.odoismonitor.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.QrCodeScanner
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import kotlinx.coroutines.launch
import me.o2d.odoismonitor.R
import me.o2d.odoismonitor.data.MonitorRepository

/** Primeiro acesso: lê o QR code de *Acesso remoto → Parear celular…* no Mac. */
@Composable
fun PairScreen(repo: MonitorRepository, initialError: String? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf(initialError) }
    var manual by remember { mutableStateOf(false) }
    var code by remember { mutableStateOf("") }

    fun submit(raw: String) {
        busy = true
        scope.launch {
            error = repo.pair(raw)
            busy = false
        }
    }

    Column(
        Modifier.fillMaxSize().padding(28.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp, Alignment.CenterVertically),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Image(painterResource(R.mipmap.ic_launcher), null, Modifier.size(112.dp).clip(RoundedCornerShape(28.dp)))
        Text("oDois Monitor", fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Text(
            "Acompanhe o monitor do seu Mac de qualquer lugar.\nNo Mac, abra o menu do monitor → Acesso remoto → Parear celular… e leia o QR code.",
            color = Palette.secondary, textAlign = TextAlign.Center,
        )
        Button(
            onClick = {
                val options = GmsBarcodeScannerOptions.Builder().setBarcodeFormats(Barcode.FORMAT_QR_CODE).build()
                GmsBarcodeScanning.getClient(context, options).startScan()
                    .addOnSuccessListener { barcode -> barcode.rawValue?.let(::submit) }
                    .addOnFailureListener { error = "Não consegui abrir o leitor de QR code. Use “Colar código”." }
            },
            enabled = !busy,
            modifier = Modifier.fillMaxWidth().height(56.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Palette.teal),
        ) {
            if (busy) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) else {
                Icon(Icons.Rounded.QrCodeScanner, null); HGap(8.dp); Text("Ler QR code", fontWeight = FontWeight.Bold)
            }
        }
        if (manual) {
            OutlinedTextField(code, { code = it }, label = { Text("Código de pareamento") }, modifier = Modifier.fillMaxWidth(), minLines = 3)
            Button(onClick = { submit(code) }, enabled = !busy && code.isNotBlank(), modifier = Modifier.fillMaxWidth()) { Text("Parear") }
        } else {
            TextButton(onClick = { manual = true }) { Text("Colar código") }
        }
        error?.let { Text(it, color = Palette.red, textAlign = TextAlign.Center) }
    }
}

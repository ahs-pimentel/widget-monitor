package me.o2d.odoismonitor.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import kotlinx.serialization.json.Json
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Pareamento com o Mac. O token é cifrado com AES-256-GCM por uma chave do Android
 * Keystore (não exportável, presa a este aparelho) antes de ir para as preferências.
 * Nunca é exibido nem registrado em log.
 */
class PairingStore(context: Context) {
    private val prefs = context.getSharedPreferences("pairing", Context.MODE_PRIVATE)

    fun load(): PairingInfo? {
        val url = prefs.getString("url", null) ?: return null
        val sealed = prefs.getString("token", null) ?: return null
        val token = runCatching { decrypt(sealed) }.getOrNull() ?: return null
        return PairingInfo(
            url = url, token = token,
            host = prefs.getString("host", "Mac") ?: "Mac",
            device = prefs.getString("device", "Celular") ?: "Celular",
        )
    }

    fun save(info: PairingInfo) {
        prefs.edit()
            .putString("url", info.url.trimEnd('/'))
            .putString("token", encrypt(info.token))
            .putString("host", info.host)
            .putString("device", info.device)
            .apply()
    }

    fun clear() = prefs.edit().clear().apply()

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    /** IV (12 bytes) + texto cifrado, em Base64. */
    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION).apply { init(Cipher.ENCRYPT_MODE, key()) }
        val sealed = cipher.iv + cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(sealed, Base64.NO_WRAP)
    }

    private fun decrypt(encoded: String): String {
        val bytes = Base64.decode(encoded, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORMATION).apply {
            init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, 12))
        }
        return String(cipher.doFinal(bytes, 12, bytes.size - 12), Charsets.UTF_8)
    }

    companion object {
        private const val KEYSTORE = "AndroidKeyStore"
        private const val ALIAS = "odois-monitor-pairing"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private val json = Json { ignoreUnknownKeys = true }

        /** Lê o JSON do QR code; aceita só HTTPS e token não vazio. */
        fun parse(raw: String): PairingInfo? = runCatching {
            json.decodeFromString(PairingInfo.serializer(), raw.trim())
        }.getOrNull()?.takeIf { it.url.startsWith("https://") && it.token.length >= 20 }
    }
}

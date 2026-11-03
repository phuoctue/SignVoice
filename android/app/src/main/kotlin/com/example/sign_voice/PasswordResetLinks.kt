package com.example.sign_voice

import java.net.URI

/** Only a reset token may enter the native navigator from an external Intent. */
object PasswordResetLinks {
    fun route(value: String?, allowedHost: String): String? {
        if (value == null || value.length > 2048) return null
        return try {
            val uri = URI(value)
            if (uri.rawUserInfo != null) return null
            val custom = uri.scheme == "signvoice" && uri.host == "reset-password" && uri.path.isNullOrEmpty()
            val web = uri.scheme in listOf("http", "https") && uri.host.equals(allowedHost, ignoreCase = true) && uri.path == "/auth/reset-password"
            if (!custom && !web) return null
            val proof = if (custom) uri.rawQuery else uri.rawFragment
            if (!Regex("token=[a-f0-9]{64}").matches(proof ?: "")) return null
            if (custom && uri.rawFragment != null || web && uri.rawQuery != null) return null
            "/reset-password?" + proof
        } catch (_: Exception) { null }
    }
}

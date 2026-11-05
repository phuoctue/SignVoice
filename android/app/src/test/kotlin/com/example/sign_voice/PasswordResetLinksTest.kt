package com.example.sign_voice

import org.junit.Assert.*
import org.junit.Test

class PasswordResetLinksTest {
    private val token = "a".repeat(64)
    @Test fun acceptsOnlyResetLinks() {
        assertEquals("/reset-password?token=$token", PasswordResetLinks.route("signvoice://reset-password?token=$token", "localhost"))
        assertEquals("/reset-password?token=$token", PasswordResetLinks.route("http://localhost:3003/auth/reset-password#token=$token", "localhost"))
        assertEquals("/reset-password?token=$token", PasswordResetLinks.route("https://signvoice.example/auth/reset-password#token=$token", "signvoice.example"))
        for (url in listOf("signvoice://admin?token=$token", "https://evil.test/auth/reset-password#token=$token",
            "https://evil.test@localhost/auth/reset-password#token=$token", "signvoice://reset-password?token=bad",
            "signvoice://reset-password?token=$token&next=admin", "http://localhost:3003/auth/reset-password?token=$token",
            "signvoice://reset-password?token=$token#ignored")) assertNull(url, PasswordResetLinks.route(url, "localhost"))
    }
}

package com.example.sign_voice

import android.app.Activity
import android.content.MutableContextWrapper
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import androidx.credentials.ClearCredentialStateRequest
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.exceptions.ClearCredentialException
import androidx.credentials.exceptions.GetCredentialCancellationException
import androidx.credentials.exceptions.GetCredentialException
import androidx.credentials.exceptions.NoCredentialException
import com.google.android.libraries.identity.googleid.GetSignInWithGoogleOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executor

/** Google proof is returned to the server for verification, never used as an app session. */
class NativeGoogleSignIn(private val activity: Activity) {
    private val manager by lazy { CredentialManager.create(activity) }
    private val handler = Handler(Looper.getMainLooper())
    private val executor = Executor { handler.post(it) }
    private var pending: MethodChannel.Result? = null
    private var cancellation: CancellationSignal? = null
    private var timeout: Runnable? = null

    fun signIn(clientId: String?, nonce: String?, result: MethodChannel.Result) {
        if (pending != null) { result.error("GOOGLE_BUSY", "Google sign-in is already open", null); return }
        if (clientId.isNullOrBlank() || !clientId.endsWith(".apps.googleusercontent.com") || nonce.isNullOrBlank()) {
            result.error("GOOGLE_CONFIGURATION", "Missing Google configuration", null); return
        }
        pending = result
        val signal = CancellationSignal()
        cancellation = signal
        val deadline = Runnable {
            if (pending === result) { finish(result, "GOOGLE_TIMEOUT"); signal.cancel() }
        }
        timeout = deadline
        handler.postDelayed(deadline, 180000)
        try {
            val option = GetSignInWithGoogleOption.Builder(clientId).setNonce(nonce).build()
            val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
            manager.getCredentialAsync(MutableContextWrapper(activity), request, signal, executor,
                object : CredentialManagerCallback<GetCredentialResponse, GetCredentialException> {
                    override fun onResult(value: GetCredentialResponse) {
                        if (pending !== result) return
                        try {
                            val credential = value.credential
                            if (credential !is CustomCredential || credential.type != GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                                finish(result, "GOOGLE_INVALID_RESPONSE"); return
                            }
                            val token = GoogleIdTokenCredential.createFrom(credential.data).idToken
                            finish(result, token = token)
                        } catch (_: Exception) { finish(result, "GOOGLE_INVALID_RESPONSE") }
                    }
                    override fun onError(error: GetCredentialException) {
                        finish(result, when (error) {
                            is GetCredentialCancellationException -> "GOOGLE_CANCELLED"
                            is NoCredentialException -> "GOOGLE_NO_ACCOUNT"
                            else -> "GOOGLE_UNAVAILABLE"
                        })
                    }
                })
        } catch (_: Exception) { finish(result, "GOOGLE_UNAVAILABLE") }
    }

    private fun finish(result: MethodChannel.Result, error: String? = null, token: String? = null) {
        if (pending !== result) return
        timeout?.let { handler.removeCallbacks(it) }; timeout = null
        pending = null; cancellation = null
        if (error != null) result.error(error, "Google sign-in could not complete", null)
        else result.success(token)
    }

    fun clear(result: MethodChannel.Result) {
        cancel()
        try {
            manager.clearCredentialStateAsync(ClearCredentialStateRequest(), null, executor,
                object : CredentialManagerCallback<Void?, ClearCredentialException> {
                    override fun onResult(value: Void?) { result.success(null) }
                    override fun onError(error: ClearCredentialException) { result.success(null) }
                })
        } catch (_: Exception) { result.success(null) }
    }

    private fun cancel() {
        val signal = cancellation
        pending?.let { finish(it, "GOOGLE_CANCELLED") }
        signal?.cancel()
    }
    fun close() { cancel() }
}

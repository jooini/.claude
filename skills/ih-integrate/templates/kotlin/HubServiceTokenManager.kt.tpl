// src/main/kotlin/${BASE_PKG_PATH}/hub/HubServiceTokenManager.kt
// M2M 토큰 매니저. 만료 30초 전까지 캐시 재사용.
package ${BASE_PKG}.hub

import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.client.WebClient
import java.time.Instant

@Component
class HubServiceTokenManager(
    @Value("\${hub.url}") private val hubUrl: String,
    @Value("\${hub.realm}") private val realm: String,
    @Value("\${hub.client-id}") private val clientId: String,
) {
    private var cached: String? = null
    private var expiresAt: Instant = Instant.MIN

    @Synchronized
    fun token(): String {
        if (cached != null && Instant.now().isBefore(expiresAt.minusSeconds(30))) {
            return cached!!
        }
        val resp = WebClient.create().post()
            .uri("$hubUrl/api/v1/auth/service-token")
            .header("Content-Type", "application/json")
            .bodyValue(mapOf("client_id" to clientId, "realm" to realm))
            .retrieve()
            .bodyToMono(Map::class.java)
            .block()!!
        cached = resp["access_token"] as String
        expiresAt = Instant.now().plusSeconds((resp["expires_in"] as Number).toLong())
        return cached!!
    }
}

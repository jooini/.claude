// src/main/kotlin/${BASE_PKG_PATH}/hub/HubServiceTokenManager.kt
// M2M 토큰 매니저. 만료 30초 전까지 캐시 재사용.
// SECURITY: never log or return token raw values. 발급 토큰은 호출자에게만 반환하고 로그에 남기지 않는다.
package ${BASE_PKG}.hub

import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.client.WebClient
import org.springframework.web.reactive.function.client.WebClientResponseException
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
        val resp = try {
            WebClient.create().post()
                .uri("$hubUrl/api/v1/auth/service-token")
                .header("Content-Type", "application/json")
                .bodyValue(mapOf("client_id" to clientId, "realm" to realm))
                .retrieve()
                .bodyToMono(Map::class.java)
                .block()!!
        } catch (e: WebClientResponseException) {
            // SECURITY: Hub 응답 본문을 그대로 전파하지 않고 일반화된 예외로만 전달
            throw IllegalStateException("service_token_failed: ${e.statusCode}")
        }
        cached = resp["access_token"] as String
        expiresAt = Instant.now().plusSeconds((resp["expires_in"] as Number).toLong())
        return cached!!
    }
}

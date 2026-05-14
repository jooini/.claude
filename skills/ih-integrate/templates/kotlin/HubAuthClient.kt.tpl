// src/main/kotlin/${BASE_PKG_PATH}/hub/HubAuthClient.kt
// Hub BFF 경유 로그인 URL 생성 + 토큰 교환.
package ${BASE_PKG}.hub

import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.client.WebClient

@Component
class HubAuthClient(
    @Value("\${hub.url}") private val hubUrl: String,
    @Value("\${hub.realm}") private val realm: String,
    @Value("\${hub.client-id}") private val clientId: String,
    @Value("\${hub.redirect-uri}") private val redirectUri: String,
) {
    fun loginUrl(): String {
        val qs = listOf(
            "client_id=$clientId",
            "realm=$realm",
            "redirect_uri=$redirectUri",
            "response_mode=query",
        ).joinToString("&")
        return "$hubUrl/api/v1/auth/login?$qs"
    }

    fun exchange(code: String): Map<*, *> {
        return WebClient.create().post()
            .uri("$hubUrl/api/v1/auth/exchange")
            .header("Content-Type", "application/json")
            .bodyValue(mapOf("code" to code))
            .retrieve()
            .bodyToMono(Map::class.java)
            .block()!!
    }
}

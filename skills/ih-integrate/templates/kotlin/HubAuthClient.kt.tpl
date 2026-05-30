// src/main/kotlin/${BASE_PKG_PATH}/hub/HubAuthClient.kt
// Hub BFF 경유 로그인 URL 생성 + 토큰 교환.
// SECURITY: never log or return token raw values. exchange 결과(토큰)는 호출자에게만 반환하고
// Hub 에러 본문을 그대로 전파하지 않는다.
package ${BASE_PKG}.hub

import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Component
import org.springframework.web.reactive.function.client.WebClient
import org.springframework.web.reactive.function.client.WebClientResponseException

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
        return try {
            WebClient.create().post()
                .uri("$hubUrl/api/v1/auth/exchange")
                .header("Content-Type", "application/json")
                .bodyValue(mapOf("code" to code))
                .retrieve()
                .bodyToMono(Map::class.java)
                .block()!!
        } catch (e: WebClientResponseException) {
            // SECURITY: Hub 응답 본문을 그대로 전파하지 않고 일반화된 예외로만 전달
            throw IllegalStateException("exchange_failed: ${e.statusCode}")
        }
    }
}
